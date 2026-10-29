#!/usr/bin/env python3
"""Check WFF condition trees in the generator's actual XML on stdin."""

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

    for field in ("VALUE", "MIN", "MAX"):
        condition = fields.find(f"Condition/Expressions/Expression[@name='bounded{field}']/../..")
        value = f"[COMPLICATION.RANGED_VALUE_{field}]"
        expression = condition.find("Expressions/Expression") if condition is not None else None
        parameter = condition.find("Compare/Group/PartText/Text/Font/Template/Parameter") if condition is not None else None
        if (
            expression is None or expression.text != f"{value} >= 0 && {value} <= 800"
            or parameter is None or parameter.get("expression") != value
            or condition.find("Default/Group") is None
        ):
            errors.append(f"consumer {field} needs independent bounded actual text and fallback")
    title = fields.find("Condition/Expressions/Expression[@name='title0']/../..")
    expected_titles = [f'[COMPLICATION.TITLE] == "{value}"' for value in ("0", "1", "2", "")]
    if title is None or [item.text for item in title.findall("Expressions/Expression")] != expected_titles:
        errors.append("consumer TITLE must use the closed index/empty vocabulary")
    elif len(title.findall("Compare/Group")) != 4 or title.find("Default/Group") is None:
        errors.append("consumer TITLE needs each category and an unknown-literal fallback")

    for branch in admission.findall("Compare"):
        expression = branch.get("expression", "")
        layout, index = expression.removeprefix("is").split("Band")
        witness = branch.find(f"Group/Group[@name='n1Diag_add_admit_{layout}_{index}']")
        if witness is None or "".join(witness.itertext()).strip() != ("AN1" if layout == "N1" else "Aother"):
            errors.append(f"{expression}: admission witness must belong to the actual branch")
    n1 = admission.find("Compare[@expression='isN1Band0']/Group")
    paint = n1.find("Condition/Compare[@expression='hasRemaining']/Condition") if n1 is not None else None
    if paint is None:
        errors.append("N1 original paint selector missing")
    else:
        for path, name in (("Compare[@expression='isFull']", "full"),
                           ("Compare[@expression='isNearEmpty']", "tiny"), ("Default", "round")):
            wrapper = paint.find(f"{path}/Group[@name='n1Diag_wrap_{name}']")
            if wrapper is None or [child.tag for child in wrapper] != ["PartDraw", "Group"] or (
                wrapper[1].get("name") != f"n1Diag_add_paint_{name}"
                or "".join(wrapper[1].itertext()).strip() != f"P{name}"
            ):
                errors.append(f"N1 {name}: witness must share its actual colored-paint branch")
    if n1 is None or n1.find("Condition/Default/Group[@name='n1Diag_add_paintNone']") is None:
        errors.append("N1 no-color branch witness missing")
    if admission.find("Default/Group[@name='n1Diag_add_rejected']") is None:
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
