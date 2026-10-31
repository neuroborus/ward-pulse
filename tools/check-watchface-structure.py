#!/usr/bin/env python3
"""Check WFF condition trees and alpha gates in the generator's actual XML on stdin."""

import ast
import math
import struct
import sys
from copy import deepcopy
import xml.etree.ElementTree as ET


# Independent design dimensions: (MAX, full stroke, full/inner/outer diameters, belt end).
# Keep these literal expectations separate from the JavaScript layout calculations.
BAND_LAYOUTS = {
    "Legacy": (100, 20, ((384, 374, 394), (336, 326, 346), (288, 278, 298)), 134),
    "N1": (200, 44, ((360, 338, 382),), 158),
    "N2": (400, 32, ((372, 356, 388), (300, 284, 316)), 134),
    "N3": (800, 20, ((384, 374, 394), (336, 326, 346), (288, 278, 298)), 134),
}

N1_RESTORE = "ring1N1BackdropRestore"


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
    return (errors + check_backdrop_restore(root) + check_band_paints(root)
            + check_extra_decisions(root) + check_retained_extra_paint(root))


def paint_expression(expression):
    """Parse only the arithmetic/boolean/ternary subset emitted by the paint gates."""
    source = expression.replace("[COMPLICATION.RANGED_VALUE_VALUE]", "value")
    source = source.replace("[COMPLICATION.RANGED_VALUE_MAX]", "maximum")
    source = source.replace("[COMPLICATION.RANGED_VALUE_MIN]", "minimum")
    source = source.replace("[COMPLICATION.TITLE]", "title")
    predicate, separator, outcomes = source.partition(" ? ")
    if separator:
        when_true, separator, when_false = outcomes.partition(" : ")
        if not separator:
            raise ValueError("incomplete alpha ternary")
        source = f"({when_true}) if ({predicate}) else ({when_false})"
    source = source.replace("&&", " and ").replace("||", " or ").replace("!(", "not (")
    return ast.parse(source, mode="eval").body


def evaluate_paint(node, value, maximum, minimum=0, title=""):
    def evaluate(child):
        return evaluate_paint(child, value, maximum, minimum, title)

    if isinstance(node, ast.BoolOp) and isinstance(node.op, ast.And):
        return all(evaluate(child) for child in node.values)
    if isinstance(node, ast.BoolOp) and isinstance(node.op, ast.Or):
        return any(evaluate(child) for child in node.values)
    if isinstance(node, ast.UnaryOp) and isinstance(node.op, ast.Not):
        return not evaluate(node.operand)
    if isinstance(node, ast.IfExp):
        return evaluate(node.body if evaluate(node.test) else node.orelse)
    if isinstance(node, ast.Compare) and len(node.ops) == len(node.comparators) == 1:
        left = evaluate(node.left)
        right = evaluate(node.comparators[0])
        if isinstance(node.ops[0], ast.Eq):
            return left == right
        if isinstance(node.ops[0], ast.Gt):
            return left > right
        if isinstance(node.ops[0], ast.GtE):
            return left >= right
        if isinstance(node.ops[0], ast.Lt):
            return left < right
        if isinstance(node.ops[0], ast.LtE):
            return left <= right
    if isinstance(node, ast.BinOp):
        left, right = evaluate(node.left), evaluate(node.right)
        if isinstance(node.op, ast.Div):
            return left / right
        if isinstance(node.op, ast.Mult):
            return left * right
        if isinstance(node.op, ast.Add):
            return left + right
        if isinstance(node.op, ast.Sub):
            return left - right
    if (isinstance(node, ast.Call) and isinstance(node.func, ast.Name)
            and node.func.id == "clamp" and len(node.args) == 3 and not node.keywords):
        number, lower, upper = (evaluate(arg) for arg in node.args)
        return min(max(number, lower), upper)
    if isinstance(node, ast.Name) and node.id in ("value", "maximum", "minimum", "title"):
        return {"value": value, "maximum": maximum, "minimum": minimum, "title": title}[node.id]
    if isinstance(node, ast.Constant) and type(node.value) in (int, float, str):
        return node.value
    raise ValueError("unsupported paint expression")


def adjacent_float(value, direction):
    """The neighboring positive wire Float, on either side of a rounded boundary."""
    bits = struct.unpack("!I", struct.pack("!f", value))[0]
    return struct.unpack("!f", struct.pack("!I", bits + direction))[0]


def check_band_envelopes(root):
    errors = []
    for layout, (_, thickness, diameters, belt_end) in BAND_LAYOUTS.items():
        previous_inner = None
        for index, (full, inner, outer) in enumerate(diameters):
            edges = []
            for name, diameter, stroke in (
                (f"ring{index + 1}{layout}", full, thickness),
                (f"ring{index + 1}{layout}Half", inner, thickness / 2),
                (f"outerHalf106_{layout}_{index + 1}_full", outer, thickness / 2),
            ):
                track = root.find(f".//Group[@name='{name}']/PartDraw/Arc")
                expected = {"centerX": "225", "centerY": "225", "width": f"{diameter:g}",
                            "height": f"{diameter:g}", "startAngle": "0", "endAngle": "359.9"}
                paint = None if track is None else track.find("Stroke")
                if (track is None or track.attrib != expected or paint is None
                        or paint.attrib != {"color": "#ff2e3632", "thickness": f"{stroke:g}", "cap": "ROUND"}):
                    errors.append(f"{name}: emitted track differs from independent design geometry")
                    continue
                actual_diameter = float(track.get("width"))
                actual_stroke = float(paint.get("thickness"))
                edges.append(((actual_diameter - actual_stroke) / 2,
                              (actual_diameter + actual_stroke) / 2))
            if len(edges) != 3:
                continue
            full_edges, inner_edges, outer_edges = edges
            if (inner_edges[0] != full_edges[0] or outer_edges[1] != full_edges[1]
                    or inner_edges[1] != outer_edges[0] or full_edges[0] < belt_end - 0.2
                    or (previous_inner is None and full_edges[1] != 202)
                    or (previous_inner is not None and previous_inner - full_edges[1] != 4)):
                errors.append(f"{layout}/{index}: emitted radial edges, aperture or gapless halves drifted")
            previous_inner = full_edges[0]
        if previous_inner != belt_end:
            errors.append(f"{layout}: belt must end at {belt_end}")
    return errors


def check_paint_endpoints(arc, kind, diameter, thickness, value, maximum):
    """Evaluate emitted transforms, not reconstructed generator markup."""
    if arc is None:
        return False
    transforms = arc.findall("Transform")
    cap = round(thickness / diameter * 180 / math.pi, 2)
    start = float(arc.get("startAngle"))
    end = float(arc.get("endAngle"))
    if transforms:
        start = evaluate_paint(paint_expression(transforms[0].get("value", "")), value, maximum)
    wanted_start = 0 if kind == "full" else (1 - value / maximum) * 359.9
    wanted_end = 359.9
    if kind == "round":
        wanted_start += cap
        wanted_end -= cap
    # Legacy/N3 publish six-decimal cutoffs. Immediately above a rounded-down
    # boundary their historical clamp can collapse the centreline, with at most
    # half a last published digit of excess visible cap. New widths get no allowance.
    legacy_rounding = (kind == "round" and thickness in (10, 20)
                       and 0 <= 2 * cap - 359.9 * value / maximum <= 359.9 * 0.0000005)
    if legacy_rounding:
        wanted_start = wanted_end
    visible = end - start + (2 * cap if kind == "round" else 0)
    if not (len(transforms) == (0 if kind == "full" else 1)
            and math.isclose(start, wanted_start, rel_tol=0, abs_tol=1e-9)
            and math.isclose(end, wanted_end, rel_tol=0, abs_tol=1e-9)
            and (end > start or (legacy_rounding and end == start))
            and math.isclose(visible, 2 * cap if legacy_rounding else 359.9 * value / maximum,
                             rel_tol=0, abs_tol=1e-9)):
        return False
    if kind == "full":
        radius = diameter / 2
        half_gap = math.radians((360 - (end - start)) / 2)
        along = radius * math.cos(half_gap)
        reach = math.sqrt((thickness / 2)**2 - (radius * math.sin(half_gap))**2)
        return (0 <= along - reach - (diameter - thickness) / 2 <= 0.01
                and 0 <= (diameter + thickness) / 2 - along - reach <= 0.01)
    return True


def check_band_paints(root):
    errors = check_band_envelopes(root)
    canvas = {"x": "0", "y": "0", "width": "450", "height": "450"}
    expected = {}
    for layout, (maximum, thickness, diameters, _) in BAND_LAYOUTS.items():
        for index, (full, inner, _) in enumerate(diameters):
            for suffix in ("", "Half"):
                expected[f"ring{index + 1}{layout}{suffix}"] = (
                    maximum, inner if suffix else full, thickness / 2 if suffix else thickness)

    for name, (maximum, diameter, thickness) in expected.items():
        groups = root.findall(f".//Group[@name='{name}']")
        if len(groups) != 1:
            errors.append(f"{name}: expected one owning band Group")
            continue
        group = groups[0]
        if group.attrib != {**canvas, "name": name} or group.findall("Transform"):
            errors.append(f"{name}: band owner must retain neutral full-canvas coordinates")
        children = element_children(group)
        # The isolated backdrop is checked separately; it is not foreground paint.
        if name == "ring1N1":
            children = [child for child in children if child.get("name") != N1_RESTORE]
        if len(children) < 4 or [child.tag for child in children[:4]] != ["PartDraw"] + ["Group"] * 3:
            errors.append(f"{name}: track must precede three stable paint Groups")
            continue
        track, *decisions = children[:4]
        track_arc = track.find("Arc")
        track_stroke = track.find("Arc/Stroke")
        if (track.attrib != canvas or track_arc is None or track_stroke is None
                or track_stroke.attrib.get("color") != "#ff2e3632"):
            errors.append(f"{name}: zero must retain its track")
            continue
        alphas = [alpha_expression(decision) for decision in decisions]
        kinds = []
        for decision, expected_kind in zip(decisions, ("full", "tiny", "round")):
            if (decision.attrib != {**canvas, "name": f"{name}_{expected_kind}", "alpha": "0"}
                    or [child.tag for child in element_children(decision)] != ["Transform", "PartDraw"]):
                errors.append(f"{name}: each paint gate must be its stable named Group with one drawing")
                break
            draws = list(decision.iter("PartDraw"))
            arcs = list(decision.iter("Arc"))
            strokes = list(decision.iter("WeightedStroke"))
            if len(draws) != 1 or len(arcs) != 1 or len(strokes) != 1 or decision.find(".//Condition") is not None:
                errors.append(f"{name}: each paint gate must own one fixed drawing subtree")
                break
            draw, arc, stroke = draws[0], arcs[0], strokes[0]
            transforms = arc.findall("Transform")
            kind = "tiny" if stroke.get("cap") == "BUTT" else "round" if transforms else "full"
            kinds.append(kind)
            if (draw.find("Arc") is not arc or arc.find("WeightedStroke") is not stroke
                    or draw.attrib != {**canvas, "alpha": "255"}
                    or [child.tag for child in draw] != ["Variant", "Arc"]
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
            errors.append(f"{name}: gates must own full, tiny, round drawings in that order")
            continue
        foreground = [node for child in children for node in child.iter()]
        if (sum(node.tag == "WeightedStroke" for node in foreground) != 3
                or sum(node.tag == "PartDraw" for node in foreground) != 4
                or sum(node.tag == "Stroke" for node in foreground) != 1):
            errors.append(f"{name}: colored paint escaped its three gates")

        # Use the published geometry boundary independently of the emitted predicates.
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
            values = [evaluate_paint(alpha, value, maximum) for alpha in alphas]
            active = [kind for kind, alpha in zip(kinds, values) if alpha != 0]
            if any(alpha not in (0, 255) for alpha in values) or active != ([] if wanted == "none" else [wanted]):
                errors.append(f"{name}: {value}/{maximum} selected {active}, expected {wanted} alone")
            elif active:
                arc = decisions[kinds.index(wanted)].find("PartDraw/Arc")
                if not check_paint_endpoints(arc, wanted, diameter, thickness, value, maximum):
                    errors.append(f"{name}: {value}/{maximum} lost proportional endpoints or full closure")
    return errors


def tree_content(node):
    """Compare drawing content independently of indentation and XML comments."""
    return (node.tag, node.attrib, (node.text or "").strip(), (node.tail or "").strip(),
            [tree_content(child) for child in element_children(node)])


def check_backdrop_restore(root):
    """Check local declaration coverage, not fractional native raster coverage."""
    errors = []
    canvas = {"x": "0", "y": "0", "width": "450", "height": "450"}
    lift = root.find("Scene/PartDraw[@name='lift']")
    ellipse = None if lift is None else lift.find("Ellipse")
    fill = None if ellipse is None else ellipse.find("Fill")
    gradient = None if fill is None else fill.find("RadialGradient")
    if (lift is None or lift.attrib != {**canvas, "name": "lift"}
            or [child.tag for child in lift] != ["Ellipse"]
            or ellipse is None or ellipse.attrib != canvas
            or [child.tag for child in ellipse] != ["Fill"]
            or fill is None or fill.attrib != {"color": "#ff101412"}
            or [child.tag for child in fill] != ["RadialGradient"]
            or gradient is None or len(gradient) != 0 or gradient.attrib != {
                "centerX": "225", "centerY": "216", "radius": "279",
                "colors": "#ff18201C #ff101412 #ff0A0D0B", "positions": "0.0 0.55 1.0"}):
        errors.append("backdrop restoration requires the unchanged opaque scene lift")

    restores = root.findall(f".//Group[@name='{N1_RESTORE}']")
    owner = root.find(
        ".//ComplicationSlot[@slotId='101']/Complication[@type='RANGED_VALUE']"
        "/Condition/Compare[@expression='isValid']/Group/Condition/Compare[@expression='isN1']"
        "/Condition/Default/Group[@name='ring1N1']"
    )
    if len(restores) != 1 or owner is None or element_children(owner)[:1] != restores:
        return errors + ["only admitted unsplit N1 must restore its backdrop before foreground"]
    restore = restores[0]
    if (restore.attrib != {**canvas, "name": N1_RESTORE}
            or [child.tag for child in restore] != ["PartDraw", "PartDraw"]):
        return errors + ["N1 backdrop restore must isolate only its SOURCE and MASK in a neutral named Group"]
    source, mask = restore
    if source.attrib != {**canvas, "name": "ring1N1BackdropSource", "renderMode": "SOURCE"}:
        errors.append("N1 backdrop must be an opaque full-canvas lift SOURCE")
    source_copy = deepcopy(source)
    source_copy.attrib = {**canvas, "name": "lift"}
    if lift is None or tree_content(source_copy) != tree_content(lift):
        errors.append("N1 backdrop source must match the scene lift geometry and gradient")
    arc = mask.find("Arc")
    stroke = None if arc is None else arc.find("Stroke")
    if (mask.attrib != {**canvas, "renderMode": "MASK"}
            or [child.tag for child in mask] != ["Arc"]
            or arc is None or arc.attrib != {
                "centerX": "225", "centerY": "225", "width": "387", "height": "387",
                "startAngle": "0", "endAngle": "359.9"}
            or [child.tag for child in arc] != ["Stroke"]
            or stroke is None or len(stroke) != 0 or stroke.attrib != {
                "color": "#ffffffff", "thickness": "27", "cap": "ROUND"}):
        return errors + ["N1 restore requires the local white ROUND 180..207 arc MASK"]

    center = float(arc.get("width")) / 2
    half = float(stroke.get("thickness")) / 2
    # Include the narrow seam between ROUND endpoints, not just ideal radial edges.
    half_gap = math.radians((360 - float(arc.get("endAngle"))) / 2)
    along = center * math.cos(half_gap)
    reach = math.sqrt(half**2 - (center * math.sin(half_gap))**2)
    if not (158 < center - half == 180 < along - reach < 202 < along + reach < center + half == 207):
        errors.append("N1 restore must cross radius 202 with its inner edge inside the opaque track")
    return errors


def alpha_expression(group):
    transforms = group.findall("Transform")
    if (group.get("alpha") != "0" or len(transforms) != 1
            or set(transforms[0].attrib) != {"target", "value"}
            or transforms[0].get("target") != "alpha" or len(transforms[0]) != 0
            or (transforms[0].text or "").strip()):
        raise ValueError(f"{group.get('name')}: expected one alpha Transform on an initially hidden Group")
    expression = paint_expression(transforms[0].get("value", ""))
    if (not isinstance(expression, ast.IfExp)
            or not isinstance(expression.body, ast.Constant) or expression.body.value != 255
            or not isinstance(expression.orelse, ast.Constant) or expression.orelse.value != 0):
        raise ValueError(f"{group.get('name')}: alpha must use a 255-or-zero ternary")
    return expression


def check_extra_decisions(root):
    # Inspect the candidate's normal drawing tree; diagnostics are checked separately.
    rejected = root.find(".//ComplicationSlot[@slotId='106']/Complication[@type='RANGED_VALUE']"
                         "/Group[@name='n1Diag_add_rejected']")
    rejected_alpha = alpha_expression(rejected) if rejected is not None else None
    root = without_diagnostics(deepcopy(root))
    errors = []
    layouts = [(name, len(diameters), maximum, thickness)
               for name, (maximum, thickness, diameters, _) in BAND_LAYOUTS.items()]
    canvas = {"x": "0", "y": "0", "width": "450", "height": "450"}
    for slot_id, ordinal in ((106, 0), (109, 1)):
        slot = root.find(f".//ComplicationSlot[@slotId='{slot_id}']")
        ranged = slot.find("Complication[@type='RANGED_VALUE']") if slot is not None else None
        if ranged is None or any(child.tag != "Group" for child in ranged):
            errors.append(f"slot {slot_id}: extra must own fixed direct decision Groups")
            continue
        groups = list(ranged)
        expected = [(layout, index, maximum, thickness / 2, BAND_LAYOUTS[layout][2][index][2], kind)
                    for layout, count, maximum, thickness in layouts
                    for index in range(count - ordinal)
                    for kind in ("full", "tiny", "round", "zero")]
        if len(groups) != len(expected):
            errors.append(f"slot {slot_id}: expected ordered full/tiny/round/zero decisions for every feasible position")
            continue
        clip = slot.find("BoundingArc")
        if clip is None or clip.attrib != {
            "centerX": "225", "centerY": "225", "width": "414", "height": "414",
            "thickness": "68", "startAngle": "0", "endAngle": "359.9", "isRoundEdge": "TRUE",
        }:
            errors.append(f"slot {slot_id}: complete shared round clip changed")
        paints = []
        alphas = [alpha_expression(group) for group in groups]
        for group, (layout, index, maximum, thickness, diameter, kind) in zip(groups, expected):
            name = f"outerHalf{slot_id}_{layout}_{index + 1}_{kind}"
            if group.attrib != {**canvas, "name": name, "alpha": "0"}:
                errors.append(f"{name}: decision must be its stable named full-canvas alpha Group")
                paints.append(None)
                continue
            children = element_children(group)
            draws = children[1:]
            if [child.tag for child in children] != ["Transform"] + ["PartDraw"] * (1 if kind == "zero" else 2):
                errors.append(f"{name}: decision must own track then only its corresponding paint")
                paints.append(None)
                continue
            track = draws[0]
            track_arc = track.find("Arc")
            arc_geometry = {"centerX": "225", "centerY": "225", "width": f"{diameter:g}",
                            "height": f"{diameter:g}", "startAngle": "0", "endAngle": "359.9"}
            stroke = track.find("Arc/Stroke")
            if (track.attrib != canvas or [child.tag for child in track] != ["Arc"]
                    or track_arc is None or track_arc.attrib != arc_geometry
                    or [child.tag for child in track_arc] != ["Stroke"]
                    or stroke is None or stroke.attrib != {
                        "color": "#ff2e3632", "thickness": f"{thickness:g}", "cap": "ROUND"}):
                errors.append(f"{name}: admitted decision lost its exact track geometry")
            # The round clip must contain the complete annulus, including full-path caps.
            half_gap = math.radians(0.1 / 2)
            clip_along = 173 * math.cos(half_gap)
            clip_reach = math.sqrt(34**2 - (173 * math.sin(half_gap))**2)
            if not clip_along - clip_reach < (diameter - thickness) / 2 < (
                diameter + thickness
            ) / 2 < clip_along + clip_reach:
                errors.append(f"{name}: complete half envelope escapes clip")
            if kind == "zero":
                paints.append(None)
                continue
            paint = draws[1]
            arc = paint.find("Arc")
            weighted = paint.find("Arc/WeightedStroke")
            cap = round(thickness / diameter * 180 / math.pi, 2)
            end = 359.9 - cap if kind == "round" else 359.9
            transforms = [] if arc is None else arc.findall("Transform")
            if (paint.attrib != {**canvas, "alpha": "255"}
                    or [child.tag for child in paint] != ["Variant", "Arc"]
                    or paint[0].attrib != {"mode": "AMBIENT", "target": "alpha", "value": "140"}
                    or arc is None or arc.attrib != {**arc_geometry, "endAngle": f"{end:.2f}" if kind == "round" else "359.9"}
                    or [child.tag for child in arc] != ([] if kind == "full" else ["Transform"]) + ["WeightedStroke"]
                    or weighted is None or weighted.attrib != {
                        "thickness": f"{thickness:g}", "colors": "[COMPLICATION.RANGED_VALUE_COLORS]",
                        "cap": "BUTT" if kind == "tiny" else "ROUND"}
                    or any(set(item.attrib) != {"target", "value"} or item.get("target") != "startAngle"
                           for item in transforms)):
                errors.append(f"{name}: selected drawing lost its geometry, caps, family or ambient alpha")
            paints.append(paint_expression(transforms[0].get("value", "")) if transforms else None)
            if kind == "full":
                radius = diameter / 2
                along = radius * math.cos(half_gap)
                reach = math.sqrt((thickness / 2)**2 - (radius * math.sin(half_gap))**2)
                if not (0 <= along - reach - (diameter - thickness) / 2 <= 0.01
                        and 0 <= (diameter + thickness) / 2 - along - reach <= 0.01):
                    errors.append(f"{name}: full path no longer closes the complete annulus")

        gate_errors = set()

        def selected(value, maximum, minimum=0, title="0"):
            values = [evaluate_paint(alpha, value, maximum, minimum, title) for alpha in alphas]
            if any(alpha not in (0, 255) for alpha in values):
                gate_errors.add(f"slot {slot_id}: decision alpha must be zero or 255")
            active = [position for position, alpha in enumerate(values) if alpha != 0]
            if slot_id == 106 and rejected_alpha is not None:
                actual = evaluate_paint(rejected_alpha, value, maximum, minimum, title)
                if actual != (0 if active else 255):
                    gate_errors.add("slot 106: rejected AX/PN gate must complement actual admission")
            return active

        for layout, count, maximum, thickness in layouts:
            for index in range(3):
                # Impossible positions still exercise admission; they own no geometry.
                diameter = BAND_LAYOUTS[layout][2][index][2] if index < count else 394
                cap = round((thickness / 2) / diameter * 180 / math.pi, 2)
                cutoff = 2 * cap / 359.9
                if thickness == 20:
                    cutoff = round(cutoff, 6)
                values = [0, 2**-20 * maximum, adjacent_float(cutoff * maximum, -1),
                          adjacent_float(cutoff * maximum, 1), 0.37 * maximum, 0.99 * maximum,
                          0.996 * maximum, 0.999 * maximum, adjacent_float(maximum, -1), maximum]
                for value in values:
                    kind = ("zero" if value == 0 else "full" if value == maximum
                            else "tiny" if value / maximum <= cutoff else "round")
                    wanted = [(layout, index, maximum, thickness / 2, diameter, kind)] if index < count - ordinal else []
                    positions = selected(value, maximum, title=str(index))
                    actual = [expected[position] for position in positions]
                    if actual != wanted:
                        errors.append(f"slot {slot_id}/{layout}/{index}: {value} selected {actual}, expected {wanted}")
                    elif positions and kind != "zero":
                        arc = groups[positions[0]].findall("PartDraw")[1].find("Arc")
                        if not check_paint_endpoints(arc, kind, diameter, thickness / 2, value, maximum):
                            errors.append(f"slot {slot_id}/{layout}/{index}: selected {kind} endpoints or closure drifted")
                    if positions and kind in ("tiny", "round"):
                        transform = paints[positions[0]]
                        start = evaluate_paint(transform, value, maximum) if transform is not None else math.nan
                        wanted_start = (1 - value / maximum) * 359.9 + (cap if kind == "round" else 0)
                        if not math.isclose(start, wanted_start, rel_tol=0, abs_tol=1e-9):
                            errors.append(f"slot {slot_id}/{layout}/{index}: selected {kind} sweep is not proportional")
                malformed = [(value, maximum, 0, str(index))
                             for value in (-1, adjacent_float(maximum, 1), math.nan, math.inf, -math.inf)]
                # Exercise admission in every paint state, including the zero-only track.
                malformed += [(value, maximum, minimum, str(index))
                              for minimum in (-1, 1, math.nan, math.inf, -math.inf) for value in values]
                malformed += [(value, maximum, 0, title)
                              for title in ("", "00", "01", "+0", "0.0", " 0", "0 ", "3", "-1", "split", "0:zero")
                              for value in values]
                if any(selected(value, upper, lower, title) for value, upper, lower, title in malformed):
                    errors.append(f"slot {slot_id}/{layout}/{index}: malformed input admitted")
        if any(selected(value, maximum, title=title)
               for maximum in (0, -1, 50, 150, 300, 900, math.nan, math.inf, -math.inf)
               for value in (0, 2**-20 * 100, 50, 100, 200, 400, 800) for title in ("0", "1", "2")):
            errors.append(f"slot {slot_id}: malformed range admitted")
        # Only declaration behavior is tested here, not a renderer's retained history.
        for index in range(2 - ordinal):
            n2 = selected(148, 400, title=str(index))
            n3 = selected(296, 800, title=str(index))
            wanted_n2 = f"outerHalf{slot_id}_N2_{index + 1}_round"
            wanted_n3 = f"outerHalf{slot_id}_N3_{index + 1}_round"
            if ([groups[position].get("name") for position in n2] != [wanted_n2]
                    or [groups[position].get("name") for position in n3] != [wanted_n3]
                    or any(evaluate_paint(alphas[position], 296, 800, title=str(index)) != 0 for position in n2)
                    or any(evaluate_paint(alphas[position], 148, 400, title=str(index)) != 0 for position in n3)):
                errors.append(f"slot {slot_id}/{index}: N2-to-N3 must hide old geometry and reveal new geometry")
        errors.extend(sorted(gate_errors))
    return errors


def emitted_band_layers(root, responses):
    """Select actual emitted drawing trees in scene order, with independent slot fields.

    Usage arcs and the separately validated local backdrop mask participate. Strips,
    textures and diagnostics are outside this declaration model, not a native rasterizer.
    """
    layers = []

    def visit(node, fields, family, alpha=255):
        if not isinstance(node.tag, str):
            return
        if node.tag == "Group" and (node.get("name", "").endswith("_strip")
                                    or node.get("name", "").startswith("n1Diag_")):
            return
        if node.tag == "Condition":
            predicates = {item.get("name"): paint_expression(item.text or "")
                          for item in node.findall("Expressions/Expression")}
            for branch in node.findall("Compare"):
                if evaluate_paint(predicates[branch.get("expression")], **fields):
                    for child in branch:
                        visit(child, fields, family, alpha)
                    return
            fallback = node.find("Default")
            if fallback is not None:
                for child in fallback:
                    visit(child, fields, family, alpha)
            return
        if node.tag in ("Group", "PartDraw"):
            local_alpha = int(node.get("alpha", "255"))
            transform = node.find("Transform[@target='alpha']")
            if transform is not None:
                # A Transform replaces this node's initial alpha, rather than multiplying it.
                local_alpha = evaluate_paint(paint_expression(transform.get("value")), **fields)
            alpha = alpha * local_alpha / 255
            if alpha == 0:
                return
        if node.tag == "Group" and node.get("name") == N1_RESTORE:
            # Treat the isolated SOURCE/MASK result as backdrop, never a white track.
            mask = node.find("PartDraw[@renderMode='MASK']/Arc")
            if mask is not None:
                visit(mask, fields, "backdrop", alpha)
            return
        if node.tag == "Arc":
            stroke = node.find("Stroke")
            colored = stroke is None
            if colored:
                stroke = node.find("WeightedStroke")
            if stroke is None:
                return
            start = float(node.get("startAngle"))
            transform = node.find("Transform[@target='startAngle']")
            if transform is not None:
                start = evaluate_paint(paint_expression(transform.get("value")), **fields)
            layers.append((float(node.get("width")) / 2, float(stroke.get("thickness")),
                           start, float(node.get("endAngle")), stroke.get("cap"),
                           family if colored or family == "backdrop" else "track", alpha,
                           stroke.get("colors") if colored else stroke.get("color")))
            return
        for child in node:
            visit(child, fields, family, alpha)

    for slot in root.findall("Scene/ComplicationSlot"):
        response = responses.get(int(slot.get("slotId")))
        if response is not None:
            fields, family = response
            ranged = slot.find("Complication[@type='RANGED_VALUE']")
            if ranged is not None:
                visit(ranged, fields, family)
    return layers


def visible_band_owner(layers, radius, angle):
    owner = None
    for center, thickness, start, end, cap, family, alpha, color in layers:
        inside = start <= angle <= end and abs(radius - center) <= thickness / 2
        if cap == "ROUND":
            inside |= any(radius**2 + center**2 - 2 * radius * center * math.cos(
                math.radians(angle - endpoint)) <= (thickness / 2)**2 for endpoint in (start, end))
        if inside:
            if family == "track" and (alpha != 255 or color != "#ff2e3632"):
                raise ValueError("retained-extra protection requires the emitted opaque track")
            if family == "backdrop" and (alpha != 255 or color != "#ffffffff"):
                raise ValueError("backdrop restoration requires its opaque local mask")
            if family not in ("track", "backdrop") and color != "[COMPLICATION.RANGED_VALUE_COLORS]":
                raise ValueError("family ownership lost its response color source")
            owner = family
    return owner


def check_retained_extra_paint(root):
    errors = []

    def response(value, maximum, title, family, minimum=0):
        return ({"value": value, "maximum": maximum, "minimum": minimum, "title": title}, family)

    def expect(tree, responses, radius, angle, owner, label):
        actual = visible_band_owner(emitted_band_layers(tree, responses), radius, angle)
        if actual != owner:
            errors.append(f"{label}: visible owner {actual}, expected {owner}")

    def expect_no_restore(responses, label):
        if any(layer[5] == "backdrop" for layer in emitted_band_layers(root, responses)):
            errors.append(f"{label}: unsplit N1 restoration escaped its admission")

    # Codex37 + Cursor70/Other50. Keep EVERY extra field, including family, unchanged
    # when only the mains become singleton Codex80; NoData is a separate later step.
    extra = response(200, 400, "0", "Other")
    paired = {101: response(280, 400, "split:cursor-other", "Cursor"),
              102: response(148, 400, "", "Codex"), 106: extra}
    expect(root, paired, 194, 300, "Other", "original pair outer half")
    expect(root, paired, 178, 300, "Cursor", "original pair inner half")
    expect(root, paired, 150, 300, "Codex", "original Codex37")
    changed = {101: response(160, 200, "", "Codex"), 106: extra}
    for radius in (186.1, 194, 201.9):
        expect(root, changed, radius, 300, "Codex", "main-only Codex80 with retained Other50")
        expect(root, changed, radius, 30, "track", "main-only spent region")
        expect(root, {101: changed[101]}, radius, 300, "Codex", "later extra NoData")
    # Prove this behavioral regression distinguishes the former scene order.
    old = deepcopy(root)
    scene = old.find("Scene")
    for slot in list(scene):
        if slot.tag == "ComplicationSlot" and slot.get("slotId") in ("106", "109"):
            scene.remove(slot)
            scene.append(slot)
    if visible_band_owner(emitted_band_layers(old, changed), 194, 300) != "Other":
        errors.append("retained-extra counterexample no longer exposes the old order")

    # Missing restoration and a mask ending on the foreground edge must both fail.
    # These are declaration counterexamples, not an antialiasing simulation.
    for thickness in (None, "17"):
        broken = deepcopy(root)
        owner = broken.find(".//Group[@name='ring1N1']")
        restore = None if owner is None else owner.find(f"Group[@name='{N1_RESTORE}']")
        if restore is None:
            errors.append("N1 coverage counterexample requires the emitted restoration")
            continue
        if thickness is None:
            owner.remove(restore)
        else:
            restore.find("PartDraw[@renderMode='MASK']/Arc/Stroke").set("thickness", thickness)
        if not check_backdrop_restore(broken) or visible_band_owner(
            emitted_band_layers(broken, changed), 203, 300
        ) == "backdrop":
            errors.append("missing or insufficient N1 restoration no longer fails the coverage contract")

    for slot_id in (106, 109):
        for value in (0, 2**-20 * 200, 74, 198, 199.2, 199.8, adjacent_float(200, -1), 200):
            title = "zero" if value == 0 else ""
            state = {101: response(value, 200, title, "Codex"), slot_id: extra}
            expect(root, state, 194, 300, "Codex" if value >= 74 else "track", "zero/tiny/partial/full protection")
            if 0 < value < 1:
                expect(root, state, 180, 359.9 - 2**-21 * 359.9, "Codex", "tiny main stays visible")
            for angle in (0, 30, 180, 300, 359.95):
                expect(root, state, 203, angle, "backdrop", "restore across outer contour, including seam")
            expect(root, state, 157.9, 300, None, "restore stays outside aperture")
            expect(root, state, 207.1, 300, None, "restore stays inside existing extra clip radius")

    for title in ("", "zero", "D", "7D", "M"):
        for value in (0, 160, 200):
            expect(root, {101: response(value, 200, title, "Codex")}, 203, 300,
                   "backdrop", "all admitted unsplit N1 titles retain restoration")
    for base in ("split", "split:cursor-other", "split:spark"):
        for suffix in ("", ":zero-inner", ":zero-outer", ":zero-both"):
            for value in (0, 160, 200):
                expect_no_restore({101: response(value, 200, base + suffix, "Codex")}, "N1 pair")
    for maximum in (100, 400, 800):
        expect_no_restore({101: response(maximum * 0.8, maximum, "", "Codex")}, "other layout")
    rejected = [response(value, maximum, title, "Codex", minimum)
                for value, maximum, minimum, title in (
                    (-1, 200, 0, ""), (201, 200, 0, ""), (math.nan, 200, 0, ""),
                    (0, 200, 1, ""), (0, 200, math.nan, ""), (0, 0, 0, ""),
                    (0, math.nan, 0, ""), (160, 200, 0, "split:unknown"),
                )]
    for invalid in rejected:
        expect_no_restore({101: invalid}, "rejected main")
    for slot_id in (102, 105):
        expect_no_restore({slot_id: response(160, 200, "", "Codex")}, "impossible N1 position")

    # All supported compatible positions and BOTH split ordinals keep adjacent halves.
    for layout, (maximum, _, diameters, _) in BAND_LAYOUTS.items():
        for ordinal, slot_id in enumerate((106, 109)):
            for index in range(len(diameters) - ordinal):
                _, inner, outer = diameters[index]
                main_id = (101, 102, 105)[index]
                outer_response = response(maximum / 2, maximum, str(index), "Other")
                state = {main_id: response(maximum * 0.7, maximum, "split:cursor-other", "Cursor"),
                         slot_id: outer_response}
                label = f"{layout}/ordinal{ordinal}/band{index}"
                expect_no_restore(state, f"{label} compatible pair")
                expect_no_restore({slot_id: outer_response}, f"{label} main NoData")
                expect(root, state, inner / 2, 300, "Cursor", f"{label} compatible inner")
                expect(root, state, outer / 2, 300, "Other", f"{label} compatible outer")
                expect(root, {slot_id: outer_response}, outer / 2, 300, "Other", f"{label} main NoData")
                expect(root, {slot_id: outer_response}, inner / 2, 300, None, f"{label} no invented main")

    # Producer projection of the unchanged near-full/tiny fixture, not observed
    # native fields: remainingPercent converts to Float before binary N1 scaling.
    main_value = struct.unpack("!f", struct.pack("!f", 100 - 0.1))[0] * 2
    tiny_value = 0.0625  # (100 - 99.96875) * 2 is exactly representable.
    for outer_value in (tiny_value, 0, 200):
        title = "split:spark:zero-outer" if outer_value == 0 else "split:spark"
        state = {101: response(main_value, 200, title, "Codex"),
                 106: response(outer_value, 200, "0", "Spark")}
        label = f"near-full Codex / Spark{outer_value}"
        layers = emitted_band_layers(root, state)
        main_paints = [layer for layer in layers if layer[5] == "Codex"]
        outer_paints = [layer for layer in layers if layer[5] == "Spark"]
        if len(main_paints) != 1 or len(outer_paints) != (0 if outer_value == 0 else 1):
            errors.append(f"{label}: independent main/outer paint must not be suppressed or duplicated")
        else:
            center, thickness, start, end, cap, _, alpha, color = main_paints[0]
            visible = end - start + 2 * round(22 / 338 * 180 / math.pi, 2)
            if ((center, thickness, cap, alpha, color)
                    != (169, 22, "ROUND", 255, "[COMPLICATION.RANGED_VALUE_COLORS]")
                    or not math.isclose(visible, main_value / 200 * 359.9, rel_tol=0, abs_tol=1e-9)):
                errors.append(f"{label}: actual Float projection lost the proportional main declaration")
        for angle in (10, 90, 180, 270, 350):
            expect(root, state, 169, angle, "Codex", f"{label} large inner")
        expect(root, state, 169, 0, "track", f"{label} main spent gap")
        expect(root, state, 191, 300, "Spark" if outer_value == 200 else "track", f"{label} outer")
        if outer_value == tiny_value:
            expect(root, state, 191, 359.9 - tiny_value / 200 * 359.9 / 2, "Spark", f"{label} tiny outer")
        expect_no_restore(state, label)

    # The emitted-gate assertions must reject both a suppressed ordinary main
    # and an overlapping full path, rather than hiding either with first-true selection.
    for overlap in (False, True):
        broken = deepcopy(root)
        round_gate = broken.find(".//Group[@name='ring1N1Half_round']/Transform")
        full_gate = broken.find(".//Group[@name='ring1N1Half_full']/Transform")
        if round_gate is None or full_gate is None:
            errors.append("near-full counterexamples require the emitted stable main gates")
            continue
        if overlap:
            full_gate.set("value", round_gate.get("value"))
        else:
            round_gate.set("value", "(0 == 1) ? 255 : 0")
        if not check_band_paints(broken):
            errors.append("suppressed or overlapping main paint no longer fails emitted-gate coverage")
    return errors


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
        **({"alpha": "0"} if group.get("name") == "n1Diag_add_rejected" else {}),
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
    decisions = [group for group in ranged.findall("Group") if group.get("name", "").startswith("outerHalf106_")]
    rejected = ranged.find("Group[@name='n1Diag_add_rejected']")
    if fields is None or not decisions or rejected is None or list(ranged) != [fields, *decisions, rejected]:
        return errors + ["consumer fields must precede and be independent of admission"]
    allowed_tags = {"Group", "Condition", "Expressions", "Expression", "Compare", "Default",
                    "PartText", "Text", "Font", "Template", "Parameter", "Transform"}
    if any(node.tag not in allowed_tags for group in additions for node in group.iter()
           if isinstance(node.tag, str)):
        errors.append("diagnostics may add only consumer text and its gates, never drawing content")
    if {node for group in additions for node in group.iter("Transform")} != {rejected.find("Transform")}:
        errors.append("only the rejected diagnostic Group may add a Transform")

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

    expected_additions = {"n1Diag_add_fields", "n1Diag_add_titleOther"}
    expected_additions.update(f"n1Diag_add_{name}" for field in ("VALUE", "MIN", "MAX")
                              for name in (f"field_{field}", f"field_{field}_other"))
    expected_additions.update(f"n1Diag_add_title{index}" for index in range(4))
    for group in decisions:
        _, layout, band, kind = group.get("name", "").split("_")
        index = int(band) - 1
        name = f"n1Diag_add_admit_{layout}_{index}_{kind}"
        expected_additions.add(name)
        witness = group.find(f"Group[@name='{name}']")
        if static_readout(witness) != ("A1" if layout == "N1" else "AO"):
            errors.append(f"{group.get('name')}: admission witness must belong to the actual decision")
        wanted = ["Transform"] + ["PartDraw"] * (1 if kind == "zero" else 2) + ["Group"]
        if layout == "N1":
            paint_name = "n1Diag_add_paintNone" if kind == "zero" else f"n1Diag_add_paint_{kind}"
            expected_additions.add(paint_name)
            paint_witness = group.find(f"Group[@name='{paint_name}']")
            if static_readout(paint_witness) != {"full": "PF", "tiny": "PT", "round": "PR", "zero": "PN"}[kind]:
                errors.append(f"N1 {kind}: witness must share its actual paint decision")
            wanted.append("Group")
        if [child.tag for child in group] != wanted:
            errors.append(f"{group.get('name')}: witnesses must follow track and selected drawing")
    if ([child.tag for child in rejected] != ["Transform", "PartText", "PartText"]
            or [static_readout(text) for text in rejected.findall("PartText")] != ["AX", "PN"]):
        errors.append("actual rejected-admission witness missing")
    expected_additions.add("n1Diag_add_rejected")
    if set(names) != expected_additions:
        errors.append("diagnostics must contain only the closed consumer-field and decision witnesses")

    # Box corners bound the maximum radius; the nearest box point bounds the minimum.
    readouts = {text for group in additions for text in group.iter("PartText")}
    for text in readouts:
        x, y, width, height = (float(text.get(key)) for key in ("x", "y", "width", "height"))
        font = text.find("Text/Font")
        if (x not in (173, 208, 243) or y not in (364, 376) or (width, height) != (34, 12)
                or font is None or font.attrib != {
                    "family": "SYNC_TO_DEVICE", "size": "10", "weight": "BOLD", "color": "#fff4fbf8"}):
            errors.append("diagnostics must preserve the six-cell footprint and readable text style")
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
    print("watchface condition trees, alpha gates and drawing containment passed")


if __name__ == "__main__":
    main()
