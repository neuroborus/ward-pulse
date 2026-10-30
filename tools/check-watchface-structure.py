#!/usr/bin/env python3
"""Check WFF condition trees in the generator's actual XML on stdin."""

import ast
import math
import struct
import sys
from copy import deepcopy
import xml.etree.ElementTree as ET


def element_children(element):
    return [child for child in element if isinstance(child.tag, str)]


def check_structure(root):
    errors = []
    owners = {node: slot.get("slotId") for slot in root.iter("ComplicationSlot") for node in slot.iter()}
    for branch in root.iter():
        if branch.tag not in ("Compare", "Default"):
            continue
        children = element_children(branch)
        if len(children) != 1:
            label = branch.get("expression", "Default")
            location = f"slot {owners[branch]}" if branch in owners else "scene"
            errors.append(
                f"{location} {label}: expected one element tree, "
                f"found {len(children)} ({', '.join(child.tag for child in children)})"
            )

    # Main admission must retain the layout selector followed by its own strip.
    for slot_id, ring in (("101", 1), ("102", 2), ("105", 3)):
        gates = root.findall(
            f".//ComplicationSlot[@slotId='{slot_id}']/Complication[@type='RANGED_VALUE']"
            "/Condition/Compare[@expression='isValid']"
        )
        if len(gates) != 1:
            errors.append(f"slot {slot_id}: expected one main admission gate")
            continue
        trees = element_children(gates[0])
        if len(trees) != 1:
            continue  # Already reported by the branch cardinality check.
        tree = trees[0]
        if tree.tag != "Group" or tree.attrib != {
            "x": "0", "y": "0", "width": root.get("width"),
            "height": root.get("height"), "name": f"ring{ring}_main",
        }:
            errors.append(f"slot {slot_id}: main tree must be its named full-canvas Group")
        children = element_children(tree)
        if len(children) != 2 or [child.tag for child in children] != ["Condition", "Group"]:
            errors.append(f"slot {slot_id}: main tree must contain selector then strip")
            continue
        selector, strip = children
        if (
            selector.find("Expressions/Expression") is None or not selector.findall("Compare")
            or selector.find(".//Arc") is None
        ):
            errors.append(f"slot {slot_id}: main layout selector lost its band drawing")
        if (
            strip.get("name") != f"ring{ring}_strip" or strip.find(".//RoundRectangle") is None
            or strip.find(".//PartText") is None
        ):
            errors.append(f"slot {slot_id}: main strip lost its well or label")
    return errors + check_band_paints(root)


def paint_expression(expression):
    """Parse only the arithmetic/boolean subset emitted by the paint selector."""
    source = expression.replace("[COMPLICATION.RANGED_VALUE_VALUE]", "value")
    source = source.replace("[COMPLICATION.RANGED_VALUE_MAX]", "maximum")
    return ast.parse(source.replace("&&", " and "), mode="eval").body


def evaluate_paint(node, value, maximum):
    if isinstance(node, ast.BoolOp) and isinstance(node.op, ast.And):
        return all(evaluate_paint(child, value, maximum) for child in node.values)
    if isinstance(node, ast.Compare) and len(node.ops) == len(node.comparators) == 1:
        left = evaluate_paint(node.left, value, maximum)
        right = evaluate_paint(node.comparators[0], value, maximum)
        if isinstance(node.ops[0], ast.Gt):
            return left > right
        if isinstance(node.ops[0], ast.GtE):
            return left >= right
        if isinstance(node.ops[0], ast.LtE):
            return left <= right
    if isinstance(node, ast.BinOp) and isinstance(node.op, ast.Div):
        return evaluate_paint(node.left, value, maximum) / evaluate_paint(node.right, value, maximum)
    if isinstance(node, ast.Name) and node.id in ("value", "maximum"):
        return value if node.id == "value" else maximum
    if isinstance(node, ast.Constant) and type(node.value) in (int, float):
        return node.value
    raise ValueError("unsupported paint expression")


def adjacent_float(value, direction):
    """The neighboring positive wire Float, on either side of a rounded boundary."""
    bits = struct.unpack("!I", struct.pack("!f", value))[0]
    return struct.unpack("!f", struct.pack("!I", bits + direction))[0]


def check_band_paints(root):
    errors = []
    expected = {}
    for layout, count, maximum in (("Legacy", 3, 100), ("N1", 1, 200),
                                    ("N2", 2, 400), ("N3", 3, 800)):
        for index in range(count):
            for suffix in ("", "Half"):
                expected[f"ring{index + 1}{layout}{suffix}"] = maximum
            for slot, ordinal in ((106, 0), (109, 1)):
                if index < count - ordinal:
                    expected[f"outerHalf{slot}_{layout}_{index + 1}"] = maximum

    for name, maximum in expected.items():
        groups = root.findall(f".//Group[@name='{name}']")
        if len(groups) != 1:
            errors.append(f"{name}: expected one owning band Group")
            continue
        group = groups[0]
        children = element_children(group)
        if len(children) < 2 or [child.tag for child in children[:2]] != ["PartDraw", "Condition"]:
            errors.append(f"{name}: track must precede the single paint selector")
            continue
        track, selector = children[:2]
        track_arc = track.find("Arc")
        track_stroke = track.find("Arc/Stroke")
        if track_arc is None or track_stroke is None or track_stroke.attrib.get("color") != "#ff2e3632":
            errors.append(f"{name}: zero must retain its track")
            continue
        expressions = selector.findall("Expressions/Expression")
        predicates = {item.get("name"): paint_expression(item.text or "") for item in expressions}
        branches = selector.findall("Compare")
        if (len(expressions) != 3 or len(predicates) != 3 or len(branches) != 3
                or {branch.get("expression") for branch in branches} != set(predicates)):
            errors.append(f"{name}: expected three locally bound paint comparisons")
            continue
        kinds = []
        for branch in branches:
            draws = list(branch.iter("PartDraw"))
            arcs = list(branch.iter("Arc"))
            strokes = list(branch.iter("WeightedStroke"))
            if len(draws) != 1 or len(arcs) != 1 or len(strokes) != 1 or branch.find(".//Condition") is not None:
                errors.append(f"{name}: each paint comparison must own one drawing subtree")
                break
            draw, arc, stroke = draws[0], arcs[0], strokes[0]
            transforms = arc.findall("Transform")
            kind = "tiny" if stroke.get("cap") == "BUTT" else "round" if transforms else "full"
            kinds.append(kind)
            if (draw.find("Arc") is not arc or arc.find("WeightedStroke") is not stroke
                    or draw.get("alpha") != "255"
                    or draw.find("Variant[@mode='AMBIENT'][@target='alpha'][@value='140']") is None
                    or stroke.get("colors") != "[COMPLICATION.RANGED_VALUE_COLORS]"
                    or stroke.get("thickness") != track_stroke.get("thickness")
                    or stroke.get("cap") != ("BUTT" if kind == "tiny" else "ROUND")
                    or any(arc.get(key) != track_arc.get(key)
                           for key in ("centerX", "centerY", "width", "height", "startAngle"))
                    or len(transforms) != (0 if kind == "full" else 1)
                    or any(item.get("target") != "startAngle" for item in transforms)):
                errors.append(f"{name}: paint lost its band geometry, family source or ambient alpha")
        if kinds != ["full", "tiny", "round"]:
            errors.append(f"{name}: comparisons must own full, tiny, round drawings in that order")
            continue
        if (len(list(group.iter("WeightedStroke"))) != 3
                or len(list(group.iter("PartDraw"))) != 4
                or len(list(group.iter("Stroke"))) != 1):
            errors.append(f"{name}: colored paint escaped its three comparisons")
        fallback = selector.find("Default")
        if fallback is not None and (name != "outerHalf106_N1_1" or
                                    fallback.find("Group[@name='n1Diag_add_paintNone']") is None):
            errors.append(f"{name}: only the diagnostic no-color fallback is allowed")

        # Use the published geometry boundary independently of the emitted predicates.
        diameter = float(track_arc.get("width"))
        thickness = float(track_stroke.get("thickness"))
        cap = round(thickness / diameter * 180 / math.pi, 2)
        cutoff = 2 * cap / 359.9
        if thickness in (10, 20):
            cutoff = round(cutoff, 6)  # Preserve the Legacy/N3 published rounding.
        cases = [(0, "none"), (2**-20 * maximum, "tiny"),
                 (adjacent_float(cutoff * maximum, -1), "tiny"),
                 (adjacent_float(cutoff * maximum, 1), "round"),
                 (0.37 * maximum, "round"),  # Exactly 74/200 for N1.
                 (0.99 * maximum, "round"), (0.996 * maximum, "round"),
                 (0.999 * maximum, "round"), (adjacent_float(maximum, -1), "round"),
                 (maximum, "full")]
        for value, wanted in cases:
            # WFF uses the first true Compare, not expression declaration order.
            actual = next((kind for branch, kind in zip(branches, kinds)
                           if evaluate_paint(predicates[branch.get("expression")], value, maximum)), "none")
            if actual != wanted:
                errors.append(f"{name}: {value}/{maximum} selected {actual}, expected {wanted}")
    return errors


def tree_content(node):
    """Compare drawing content independently of indentation and XML comments."""
    return (node.tag, node.attrib, (node.text or "").strip(), (node.tail or "").strip(),
            [tree_content(child) for child in element_children(node)])


def without_diagnostics(node):
    for child in list(node):
        if child.tag == "Default" and len(child) == 1 and (
            child[0].get("name", "").startswith("n1Diag_add_")
        ):
            node.remove(child)
        elif child.get("name", "").startswith("n1Diag_add_"):
            node.remove(child)
        else:
            without_diagnostics(child)
            if child.get("name", "").startswith("n1Diag_wrap_"):
                index = list(node).index(child)
                node.remove(child)
                for original in reversed(list(child)):
                    node.insert(index, original)
    return node


def static_readout(node):
    """Read one literal Font without hiding renderable padding or nested content."""
    if node is None:
        return None
    fonts = node.findall(".//Font")
    if len(fonts) != 1 or len(fonts[0]):
        return None
    return fonts[0].text


def check_diagnostics(root, baseline):
    errors = []
    owners = {node: slot.get("slotId") for slot in root.iter("ComplicationSlot") for node in slot.iter()}
    groups = list(root.iter("Group"))
    additions = [group for group in groups if group.get("name", "").startswith("n1Diag_")]
    names = [group.get("name") for group in additions]
    if len(names) != len(set(names)):
        errors.append("diagnostic Group names must be present, stable and unique")
    if not additions or any(owners.get(group) != "106" for group in additions):
        errors.append("N1 diagnostics must be present exclusively in slot 106")
    if any(group.attrib != {
        "x": "0", "y": "0", "width": root.get("width"), "height": root.get("height"),
        "name": group.get("name"),
    } for group in additions):
        errors.append("diagnostic groups must retain neutral full-canvas coordinates and attributes")
    if len(list(root.iter("ComplicationSlot"))) != 8:
        errors.append("diagnostics must retain exactly eight slots")
    if tree_content(without_diagnostics(deepcopy(root))) != tree_content(baseline):
        errors.append("removing diagnostics must recover all original drawing content")

    ranged = root.find(".//ComplicationSlot[@slotId='106']/Complication[@type='RANGED_VALUE']")
    if ranged is None:
        return errors + ["slot 106 ranged consumer missing"]
    fields = ranged.find("Group[@name='n1Diag_add_fields']")
    admission = ranged.find("Condition")
    if fields is None or admission is None or list(ranged) != [fields, admission]:
        return errors + ["consumer fields must precede and be independent of admission"]

    for field, label in (("VALUE", "V"), ("MIN", "m"), ("MAX", "M")):
        condition = fields.find(f"Condition/Expressions/Expression[@name='bounded{field}']/../..")
        value = f"[COMPLICATION.RANGED_VALUE_{field}]"
        expression = condition.find("Expressions/Expression") if condition is not None else None
        parameter = condition.find("Compare/Group/PartText/Text/Font/Template/Parameter") if condition is not None else None
        if (
            expression is None or expression.text != f"{value} >= 0 && {value} <= 800"
            or parameter is None or parameter.get("expression") != value
            or static_readout(condition.find("Default/Group")) != f"{label}?"
        ):
            errors.append(f"consumer {field} needs independent bounded actual text and fallback")
    title = fields.find("Condition/Expressions/Expression[@name='title0']/../..")
    expected_titles = [f'[COMPLICATION.TITLE] == "{value}"' for value in ("0", "1", "2", "")]
    if title is None or [item.text for item in title.findall("Expressions/Expression")] != expected_titles:
        errors.append("consumer TITLE must use the closed index/empty vocabulary")
    elif len(title.findall("Compare/Group")) != 4 or title.find("Default/Group") is None:
        errors.append("consumer TITLE needs each category and an unknown-literal fallback")
    else:
        for path, token in (("Compare[@expression='title0']", "T0"),
                            ("Compare[@expression='title1']", "T1"),
                            ("Compare[@expression='title2']", "T2"),
                            ("Compare[@expression='title3']", "TE"), ("Default", "T?")):
            witness = title.find(f"{path}/Group")
            if static_readout(witness) != token:
                errors.append("consumer TITLE must retain its closed two-character readout")

    for branch in admission.findall("Compare"):
        expression = branch.get("expression", "")
        layout, index = expression.removeprefix("is").split("Band")
        witness = branch.find(f"Group/Group[@name='n1Diag_add_admit_{layout}_{index}']")
        if static_readout(witness) != ("A1" if layout == "N1" else "AO"):
            errors.append(f"{expression}: admission witness must belong to the actual branch")
    n1 = admission.find("Compare[@expression='isN1Band0']/Group")
    paint = n1.find("Condition") if n1 is not None else None
    if paint is None:
        errors.append("N1 original paint selector missing")
    else:
        for branch, (name, token) in zip(paint.findall("Compare"),
                                         (("full", "PF"), ("tiny", "PT"), ("round", "PR"))):
            wrapper = branch.find(f"Group[@name='n1Diag_wrap_{name}']")
            if wrapper is None or [child.tag for child in wrapper] != ["PartDraw", "Group"] or (
                wrapper[1].get("name") != f"n1Diag_add_paint_{name}"
                or static_readout(wrapper[1]) != token
            ):
                errors.append(f"N1 {name}: witness must share its actual colored-paint branch")
    no_color = n1.find("Condition/Default/Group[@name='n1Diag_add_paintNone']") if n1 is not None else None
    if static_readout(no_color) != "PN":
        errors.append("N1 no-color branch witness missing")
    rejected = admission.find("Default/Group[@name='n1Diag_add_rejected']")
    if rejected is None or [static_readout(text) for text in rejected] != ["AX", "PN"]:
        errors.append("actual rejected-admission witness missing")

    # Box corners bound the maximum radius; the nearest box point bounds the minimum.
    readouts = {text for group in additions for text in group.iter("PartText")}
    for text in readouts:
        x, y, width, height = (float(text.get(key)) for key in ("x", "y", "width", "height"))
        nearest_x = max(x - 225, 225 - (x + width), 0)
        nearest_y = max(y - 225, 225 - (y + height), 0)
        if nearest_x**2 + nearest_y**2 < 139**2 or any(
            (px - 225)**2 + (py - 225)**2 >= (137 / 0.8)**2
            for px in (x, x + width) for py in (y, y + height)
        ):
            errors.append("diagnostic readout intersects clip boundary or original incident annulus")
    return errors


def main():
    parser = ET.XMLParser(target=ET.TreeBuilder(insert_comments=True))
    root = ET.parse(sys.stdin, parser=parser).getroot()
    if "--n1-pair-diagnostics" in sys.argv:
        trees = element_children(root)
        if root.tag != "N1DiagnosticComparison" or len(trees) != 2 or any(tree.tag != "WatchFace" for tree in trees):
            sys.exit("expected generated default and diagnostic WatchFace trees")
        baseline, root = trees
        errors = check_structure(root) + check_diagnostics(root, baseline)
    else:
        errors = check_structure(root)
    if errors:
        sys.exit("\n".join(errors))
    print("watchface condition trees and main selector/strip containment passed")


if __name__ == "__main__":
    main()
