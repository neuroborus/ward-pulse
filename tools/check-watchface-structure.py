#!/usr/bin/env python3
"""Check WFF condition trees, weather readings and paint gates in generated XML on stdin."""

import ast
import math
import struct
import sys
from copy import deepcopy
from pathlib import Path
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
COMPOSITION_SCALE = 225 / 202
SCALE_ATTRIBUTES = {"scaleX": str(COMPOSITION_SCALE), "scaleY": str(COMPOSITION_SCALE),
                    "pivotX": "0.5", "pivotY": "0.5"}


def element_children(element):
    return [child for child in element if isinstance(child.tag, str)]


def check_composition_scale(root):
    """Check actual WFF2 owners before the reference-coordinate semantic guards."""
    errors = []
    canvas = {"x": "0", "y": "0", "width": "450", "height": "450"}
    scene = root.find("Scene")
    if root.attrib != {"width": "450", "height": "450"} or scene is None:
        return ["whole-composition scaling must retain the 450 canvas and Scene"]
    if scene.attrib != {"backgroundColor": "#ff0a0d0b"}:
        errors.append("Scene must not carry an unsupported scale or geometry attribute")
    slots = scene.findall("ComplicationSlot")
    chrome = scene.find("Group[@name='compositionChrome']")
    clock = scene.find("DigitalClock")
    mark = scene.find("Group[@name='wardpulse']")
    carriers = slots + [chrome, clock, mark]
    if len(slots) != 8 or len(list(root.iter("ComplicationSlot"))) != 8 or any(node is None for node in carriers):
        return ["eight direct Scene slots, chrome, clock and watermark must own the scale"]
    for owner in carriers:
        if any(owner.get(key) != value for key, value in {**canvas, **SCALE_ATTRIBUTES}.items()):
            errors.append(f"{owner.tag}/{owner.get('name', owner.get('slotId'))}: use one full-face scale and normalized center pivot")
    for node in root.iter():
        if node not in carriers and any(key in node.attrib for key in ("scaleX", "scaleY")):
            errors.append(f"{node.tag}: nested/extra scale would enlarge the composition twice")
        if node.tag in ("Transform", "Variant") and node.get("target") in ("scaleX", "scaleY"):
            errors.append("composition scale must remain on its documented fixed owner")
        if node.tag == "Group" and not node.get("name"):
            errors.append("all WFF Groups need stable names")
        if node.tag in ("ComplicationSlot", "Group", "DigitalClock", "TimeText", "PartImage"):
            if any(key in node.attrib and not node.get(key).lstrip("-").isdigit()
                   for key in ("x", "y", "width", "height")):
                errors.append(f"{node.tag}: base rectangles must stay integer reference geometry")
    for owner in carriers:
        if any(node.tag in ("Transform", "Variant") and node.get("target") in
               ("x", "y", "width", "height", "pivotX", "pivotY") for node in owner):
            errors.append("full-face carrier geometry and pivot must not be overridden")
    for slot in slots:
        if slot.get("slotId") in ("101", "102", "105"):
            bound = slot.find("BoundingBox")
            if bound is None or bound.attrib != canvas:
                errors.append("main ring clips must retain the full reference canvas under their slot scale")
    chrome_children = element_children(chrome)
    if ([child.get("name") for child in chrome_children] != ["lift", "cell1Chrome", "cell2Chrome", "cell3Chrome"]
            or list(scene).index(chrome) >= min(list(scene).index(slot) for slot in slots)):
        errors.append("one scaled chrome Group must retain backdrop and all cell chrome before slots")
    for slot_id, x, y in (("201", 147, 109), ("202", 199, 95), ("203", 251, 109)):
        slot = scene.find(f"ComplicationSlot[@slotId='{slot_id}']")
        if slot is None:
            errors.append(f"missing customizable cell {slot_id}")
            continue
        rectangle = {"x": str(x), "y": str(y), "width": "52", "height": "52"}
        bound = slot.find("BoundingBox")
        if bound is None or bound.attrib != rectangle:
            errors.append(f"cell {slot_id}: bounds must transform with content at its original integer position")
        for complication in slot.findall("Complication"):
            if complication.get("type") != "EMPTY":
                group = complication.find("Group")
                if group is None or any(group.get(key) != value for key, value in rectangle.items()):
                    errors.append(f"cell {slot_id}: every populated type must share the transformed bounding box")
        # The complete transformed cell rectangle must fit the physical circle.
        for px in (x, x + 52):
            for py in (y, y + 52):
                if math.hypot((px - 225) * COMPOSITION_SCALE, (py - 225) * COMPOSITION_SCALE) >= 225:
                    errors.append(f"cell {slot_id}: effective bounds exceed the circular viewport")
    times = clock.findall("TimeText")
    if len(times) != 2 or [(node.get("y"), node.get("height"), node.find("Font").get("size"))
                           for node in times] != [("166", "90", "86"), ("175", "90", "96")]:
        errors.append("whole clocks must retain their reference sizes and placements beneath one scale")
    if any(node.get("format") != "hh:mm" or node.get("hourFormat") != "SYNC_TO_DEVICE"
           or node.find("Font").get("family") != "SYNC_TO_DEVICE" for node in times):
        errors.append("whole-clock formatting and device font identity must stay synchronized")
    images = mark.findall("PartImage")
    expected = [("193", "141", "64", "95"), ("198", "146", "54", "0")]
    if (len(images) != 2 or [(node.get("x"), node.get("y"), node.get("width"), node.get("alpha"))
                             for node in images] != expected
            or any(node.get("height") != node.get("width") or node.find("Image").get("resource") != "wardpulse_mono"
                   for node in images)):
        errors.append("watermark must retain its original square image boxes and alpha beneath one scale")
    if not math.isclose(202 * COMPOSITION_SCALE, 225, abs_tol=1e-12):
        errors.append("the effective outer edge must meet radius 225 without a reserve")
    return errors + check_texture_boxes(root)


def check_texture_boxes(root):
    """Raster sampling increases separately; XML boxes retain reference geometry."""
    expected = {}
    for count, diameters in ((1, (404,)), (2, (404, 332)), (3, (404, 356, 308))):
        prefix = "ring" if count == 3 else f"ring_n{count}_"
        for index, diameter in enumerate(diameters, 1):
            for period in ("day", "week", "month"):
                expected[f"{prefix}{index}_type_{period}"] = diameter
    errors = []
    seen = set()
    for part in root.findall(".//PartImage"):
        image = part.find("Image")
        resource = "" if image is None else image.get("resource", "")
        if not resource.startswith("ring"):
            continue
        diameter = expected.get(resource)
        if diameter is None:
            errors.append(f"unknown period texture resource {resource}")
            continue
        seen.add(resource)
        inset = str((450 - diameter) // 2)
        if (part.attrib != {"x": inset, "y": inset, "width": str(diameter),
                           "height": str(diameter), "alpha": "115"}
                or [node.attrib for node in part.findall("Variant")] !=
                [{"mode": "AMBIENT", "target": "alpha", "value": "63"}]):
            errors.append(f"{resource}: preserve reference image box/alpha beneath its single scaled slot")
    if seen != set(expected):
        errors.append("all 18 period textures must retain their reference WFF image boxes")
    return errors


def check_structure(root):
    errors = check_composition_scale(root)
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

    # Main admission owns fixed geometry Groups followed by its own strip.
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
        if len(children) < 3 or any(child.tag != "Group" for child in children):
            errors.append(f"slot {slot_id}: main tree must contain geometry Groups then strip")
            continue
        *geometries, strip = children
        if any(group.find(".//Arc") is None for group in geometries):
            errors.append(f"slot {slot_id}: main geometry lost its band drawing")
        if (
            strip.get("name") != f"ring{ring}_strip" or strip.find(".//RoundRectangle") is None
            or strip.find(".//PartText") is None
        ):
            errors.append(f"slot {slot_id}: main strip lost its well or label")
    return (errors + check_main_decisions(root) + check_backdrop_restore(root) + check_band_paints(root)
            + check_extra_decisions(root) + check_retained_extra_paint(root) + check_temperature(root))


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
    if isinstance(node, ast.UnaryOp) and isinstance(node.op, ast.USub):
        return -evaluate(node.operand)
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
    if (isinstance(node, ast.Call) and isinstance(node.func, ast.Name)
            and len(node.args) == 1 and not node.keywords):
        if node.func.id == "round":
            # Integer weather conversions have no exact half-degree ties.
            return math.floor(evaluate(node.args[0]) + 0.5)
        if node.func.id == "textLength":
            return len(evaluate(node.args[0]))
        if node.func.id == "tan":
            return math.tan(evaluate(node.args[0]))
    if isinstance(node, ast.Name) and node.id in ("value", "maximum", "minimum", "title"):
        return {"value": value, "maximum": maximum, "minimum": minimum, "title": title}[node.id]
    if isinstance(node, ast.Name) and node.id in ("true", "false"):
        return node.id == "true"
    if isinstance(node, ast.Constant) and type(node.value) in (int, float, str, bool):
        return node.value
    raise ValueError("unsupported paint expression")


def cell_value(expression, fields):
    """Evaluate the actual emitted expressions with explicit, synthetic source values."""
    for source, value in fields.items():
        expression = expression.replace(source, repr(value))
    return evaluate_paint(paint_expression(expression), 0, 0)


def cell_readouts(element, fields):
    """Follow WFF's first-true Condition branches, including the availability gate."""
    if element.tag == "Condition":
        predicates = {item.get("name"): item.text or "" for item in element.findall("Expressions/Expression")}
        for branch in element.findall("Compare"):
            if cell_value(predicates[branch.get("expression")], fields):
                return cell_readouts(branch, fields)
        fallback = element.find("Default")
        return [] if fallback is None else cell_readouts(fallback, fields)
    if element.tag == "PartText":
        font = element.find("Text/Font")
        template = font.find("Template")
        parameters = template.findall("Parameter")
        if len(parameters) != 1:
            raise ValueError("cell reading requires exactly one template parameter")
        return [(template.text.strip(), cell_value(parameters[0].get("expression", ""), fields),
                 int(font.get("size")))]
    return [reading for child in element_children(element) for reading in cell_readouts(child, fields)]


def check_temperature(root):
    errors = []
    configurations = root.findall("UserConfigurations")
    if (len(configurations) != 1 or [child.tag for child in configurations[0]] != ["ListConfiguration"]):
        return ["expected one face-local Temperature list configuration"]
    configuration = configurations[0][0]
    if configuration.attrib != {
        "id": "temperatureUnit", "displayName": "@string/temperature", "defaultValue": "auto",
    }:
        errors.append("Temperature must default to Auto using the canonical editor label")
    expected_options = [
        {"id": "auto", "displayName": "@string/temperature_auto"},
        {"id": "celsius", "displayName": "@string/temperature_celsius"},
        {"id": "fahrenheit", "displayName": "@string/temperature_fahrenheit"},
    ]
    if ([child.tag for child in configuration] != ["ListOption"] * 3
            or [child.attrib for child in configuration] != expected_options):
        errors.append("Temperature options must be Auto, Celsius and Fahrenheit with string IDs")
    strings_path = Path(__file__).resolve().parents[1] / "apps/watchface_wff/src/main/res/values/strings.xml"
    strings = {item.get("name"): item.text for item in ET.parse(strings_path).getroot().findall("string")}
    for name, label in (("temperature", "Temperature"), ("temperature_auto", "Auto"),
                        ("temperature_celsius", "Celsius (°C)"), ("temperature_fahrenheit", "Fahrenheit (°F)")):
        if strings.get(name) != label:
            errors.append(f"missing canonical temperature editor label: {name}")

    scene = root.find("Scene")
    slots = scene.findall("ComplicationSlot")
    if sorted(slot.get("slotId") for slot in slots) != ["101", "102", "105", "106", "109", "201", "202", "203"]:
        errors.append("temperature configuration must preserve all eight complication slots")
    chrome_owner = scene.find("Group[@name='compositionChrome']")
    chrome = scene.find("Group[@name='compositionChrome']/Group[@name='cell2Chrome']")
    if chrome is None:
        return errors + ["missing built-in temperature chrome"]
    for label in ("cell2", "cell3"):
        group = scene.find(f"Group[@name='compositionChrome']/Group[@name='{label}Chrome']")
        if group is None:
            errors.append(f"missing {label} weather chrome")
            continue
        gate = group.find("Condition/Expressions/Expression[@name='hasWeather']")
        if (gate is None or gate.text != "[WEATHER.IS_AVAILABLE]"
                or group.find("Condition/Compare[@expression='hasWeather']") is None
                or group.find(f"Condition/Default/Group[@name='{label}Bare']") is None):
            errors.append(f"{label}: preserve the weather availability gate and bare recess")
        if chrome_owner is None or any(list(scene).index(chrome_owner) >= list(scene).index(slot) for slot in slots):
            errors.append(f"{label}: built-in weather must remain beneath every complication slot")

    def expect_reading(temperature, unit, selection, value, suffix, size):
        fields = {"[WEATHER.TEMPERATURE]": temperature, "[WEATHER.TEMPERATURE_UNIT]": unit,
                  "[WEATHER.IS_AVAILABLE]": True, "[CONFIGURATION.temperatureUnit]": selection}
        actual = cell_readouts(chrome, fields)
        if actual != [(f"%s°{suffix}", value, size)] or any(type(item[1]) is not int for item in actual):
            errors.append(f"temperature {temperature}/{unit}/{selection}: {actual}, expected {value}°{suffix} at {size}")

    try:
        # Literal expected results are independent of the generator's conversion expressions.
        for temperature, unit, selection, value, suffix, size in (
            (0, 1, "fahrenheit", 32, "F", 18),
            (1, 1, "fahrenheit", 34, "F", 18),
            (-18, 1, "fahrenheit", 0, "F", 18),
            (-19, 1, "fahrenheit", -2, "F", 14),
            (-40, 1, "fahrenheit", -40, "F", 14),
            (37, 1, "fahrenheit", 99, "F", 18),
            (38, 1, "fahrenheit", 100, "F", 14),
            (100, 1, "fahrenheit", 212, "F", 14),
            (-73, 1, "fahrenheit", -99, "F", 14),
            (-74, 1, "fahrenheit", -101, "F", 12),
            (32, 2, "celsius", 0, "C", 18),
            (31, 2, "celsius", -1, "C", 14),
            (33, 2, "celsius", 1, "C", 18),
            (68, 2, "celsius", 20, "C", 18),
            (0, 2, "celsius", -18, "C", 14),
            (-40, 2, "celsius", -40, "C", 14),
            (211, 2, "celsius", 99, "C", 18),
            (212, 2, "celsius", 100, "C", 14),
            (-147, 2, "celsius", -99, "C", 14),
            (-148, 2, "celsius", -100, "C", 12),
            (-149, 2, "celsius", -101, "C", 12),
        ):
            expect_reading(temperature, unit, selection, value, suffix, size)
        # Auto and matching selections must preserve the original integer, including size boundaries.
        for unit, suffix, matching in ((1, "C", "celsius"), (2, "F", "fahrenheit")):
            for selection in ("auto", matching):
                for temperature, size in ((-101, 12), (-100, 12), (-99, 14), (-1, 14), (0, 18), (99, 18), (100, 14)):
                    expect_reading(temperature, unit, selection, temperature, suffix, size)
        for selection in ("auto", "celsius", "fahrenheit"):
            for unit in (-1, 0, 3):
                for temperature, size in ((-100, 12), (0, 18), (100, 14)):
                    expect_reading(temperature, unit, selection, temperature, "", size)
            # Unavailable weather must not evaluate missing temperature/unit values or draw a label.
            if cell_readouts(chrome, {"[WEATHER.IS_AVAILABLE]": False, "[CONFIGURATION.temperatureUnit]": selection}):
                errors.append(f"unavailable weather must retain its bare recess for {selection}")
    except (ValueError, SyntaxError, KeyError, TypeError, AttributeError) as error:
        errors.append(f"could not evaluate emitted temperature conditions/parameters: {error}")

    for slot_id, provider, kind in (("201", "DAY_OF_WEEK", "SHORT_TEXT"), ("202", "EMPTY", "EMPTY"),
                                    ("203", "EMPTY", "EMPTY")):
        slot = scene.find(f"ComplicationSlot[@slotId='{slot_id}']")
        if slot is None:
            continue  # Slot ownership was already reported.
        policy = slot.find("DefaultProviderPolicy")
        if policy is None or policy.attrib != {"defaultSystemProvider": provider, "defaultSystemProviderType": kind}:
            errors.append(f"slot {slot_id}: temperature selection must preserve provider defaults")
        if slot.get("supportedTypes") != "SHORT_TEXT RANGED_VALUE MONOCHROMATIC_IMAGE EMPTY" or slot.get("isCustomizable") != "TRUE":
            errors.append(f"slot {slot_id}: preserve supported provider types and customization")
        for expression in slot.iter():
            contents = (expression.text or "") + " ".join(expression.attrib.values())
            if "CONFIGURATION." in contents or "WEATHER." in contents:
                errors.append(f"slot {slot_id}: face-local temperature must not alter assigned providers")
        for complication in slot.findall("Complication"):
            kind = complication.get("type")
            if kind == "EMPTY":
                continue
            group = complication.find("Group")
            well = group.find("PartDraw") if group is not None else None
            fill = well.find("Ellipse/Fill") if well is not None else None
            if (fill is None or fill.get("color") != "#ff0b0e0c" or group.get("alpha", "255") != "255"
                    or group.find("Variant") is not None or well.get("alpha", "255") != "255"
                    or well.find("Variant") is not None):
                errors.append(f"slot {slot_id}/{kind}: provider well must remain opaque in every mode")
            if kind not in ("SHORT_TEXT", "RANGED_VALUE"):
                continue
            templates = complication.findall(".//Template")
            if len(templates) != 3 or any(
                template.text.strip() != "%s" or len(template.findall("Parameter")) != 1
                or template.find("Parameter").attrib != {"expression": "[COMPLICATION.TEXT]"}
                for template in templates
            ):
                errors.append(f"slot {slot_id}/{kind}: provider text must remain verbatim")
            try:
                for selection in ("auto", "celsius", "fahrenheit"):
                    if cell_readouts(complication, {"[COMPLICATION.TEXT]": "7°",
                                                   "[CONFIGURATION.temperatureUnit]": selection}) != [("%s", "7°", 18)]:
                        errors.append(f"slot {slot_id}/{kind}: selected-provider degrees must remain untouched")
            except (ValueError, SyntaxError, KeyError, TypeError, AttributeError) as error:
                errors.append(f"slot {slot_id}/{kind}: could not evaluate emitted provider text: {error}")
    return errors


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
            # The carriers above were checked on the actual emitted owners.
            # Compare effective geometry, while retaining reference tests below.
            if (not math.isclose(inner_edges[1] * COMPOSITION_SCALE, outer_edges[0] * COMPOSITION_SCALE, abs_tol=1e-12)
                    or (previous_inner is None and not math.isclose(full_edges[1] * COMPOSITION_SCALE, 225, abs_tol=1e-12))
                    or (previous_inner is not None and not math.isclose(
                        (previous_inner - full_edges[1]) * COMPOSITION_SCALE, 4 * COMPOSITION_SCALE, abs_tol=1e-12))):
                errors.append(f"{layout}/{index}: effective outer edge, paired join or proportional gap drifted")
            previous_inner = full_edges[0]
        if previous_inner != belt_end:
            errors.append(f"{layout}: belt must end at {belt_end}")
    return errors


def check_paint_shape(paint, kind, diameter, thickness, name, paired=False):
    """One live color source, an opaque local mask union and one ambient alpha."""
    canvas = {"x": "0", "y": "0", "width": "450", "height": "450"}
    geometry = {"centerX": "225", "centerY": "225", "width": f"{diameter:g}",
                "height": f"{diameter:g}", "startAngle": "0", "endAngle": "359.9"}
    weighted = {"thickness": f"{thickness:g}", "colors": "[COMPLICATION.RANGED_VALUE_COLORS]", "cap": "ROUND"}
    if paired and kind != "full":
        weighted["thickness"] = f"{thickness + 2:g}"
    if paint is None or paint.find(".//Condition") is not None:
        return False
    attributes = {**canvas, "alpha": "255"}
    if kind != "full":
        attributes["name"] = f"{name}_foreground"
    if (paint.attrib != attributes or paint.tag != ("PartDraw" if kind == "full" else "Group")
            or [child.tag for child in paint] != (["Variant", "Arc"] if kind == "full" else ["Variant", "PartDraw", "Group"])
            or paint[0].attrib != {"mode": "AMBIENT", "target": "alpha", "value": "140"}):
        return False
    source = paint if kind == "full" else paint[1]
    arc = source.find("Arc")
    stroke = source.find("Arc/WeightedStroke")
    if (arc is None or arc.attrib != geometry or [child.tag for child in arc] != ["WeightedStroke"]
            or stroke is None or stroke.attrib != weighted):
        return False
    if kind == "full":
        return True
    if source.attrib != {**canvas, "renderMode": "SOURCE"} or [child.tag for child in source] != ["Arc"]:
        return False
    mask = paint[2]
    if (mask.attrib != {**canvas, "name": f"{name}_mask", "renderMode": "MASK"}
            or [child.tag for child in mask] != ["PartDraw", "Group", "Group"]):
        return False
    core = mask[0]
    arc = core.find("Arc")
    stroke = core.find("Arc/Stroke")
    if (core.attrib != canvas or [child.tag for child in core] != ["Arc"]
            or arc is None or arc.attrib != geometry
            or [child.tag for child in arc] != ["Transform", "Transform", "Stroke"]
            or [item.get("target") for item in arc.findall("Transform")] != ["startAngle", "endAngle"]
            or any(set(item.attrib) != {"target", "value"} for item in arc.findall("Transform"))
            or stroke is None or stroke.attrib != {"color": "#ffffffff", "thickness": f"{thickness:g}", "cap": "BUTT"}):
        return False
    for group, side in zip(mask.findall("Group"), ("start", "end")):
        ellipse = group.find("PartDraw/Ellipse")
        if (group.attrib != {**canvas, "name": f"{name}_{side}Cap", "angle": "0", "pivotX": "0.5", "pivotY": "0.5"}
                or [child.tag for child in group] != ["Transform", "PartDraw"]
                or set(group[0].attrib) != {"target", "value"} or group[0].get("target") != "angle"
                or group[1].attrib != canvas or [child.tag for child in group[1]] != ["Ellipse"]
                or ellipse is None or ellipse.attrib != {
                    "x": str(math.floor(225 - thickness / 2)), "y": f"{225 - diameter / 2 - thickness / 2:g}",
                    "width": f"{thickness:g}", "height": f"{thickness:g}"}
                or [child.tag for child in ellipse] != ["Transform", "Transform", "Fill"]
                or [item.get("target") for item in ellipse.findall("Transform")] != ["x", "width"]
                or any(set(item.attrib) != {"target", "value"} for item in ellipse.findall("Transform"))
                or ellipse[-1].attrib != {"color": "#ffffffff"}):
            return False
    return True


def paint_attribute(node, attribute, value, maximum):
    transform = node.find(f"Transform[@target='{attribute}']")
    return (float(node.get(attribute)) if transform is None else
            evaluate_paint(paint_expression(transform.get("value", "")), value, maximum))


def check_paint_endpoints(paint, kind, diameter, thickness, value, maximum):
    """Evaluate the emitted core, cap placement and ellipse dimensions independently."""
    if paint is None:
        return False
    if kind == "full":
        arc = paint.find("Arc")
        if arc is None:
            return False
        start = paint_attribute(arc, "startAngle", value, maximum)
        end = paint_attribute(arc, "endAngle", value, maximum)
        radius = diameter / 2
        half_gap = math.radians((360 - (end - start)) / 2)
        along = radius * math.cos(half_gap)
        reach = math.sqrt((thickness / 2)**2 - (radius * math.sin(half_gap))**2)
        return (start == 0 and end == 359.9 and not arc.findall("Transform")
                and 0 <= along - reach - (diameter - thickness) / 2 <= 0.01
                and 0 <= (diameter + thickness) / 2 - along - reach <= 0.01)
    mask = paint.find("Group[@renderMode='MASK']")
    if mask is None:
        return False
    core = mask.find("PartDraw/Arc")
    if core is None:
        return False
    radius, half = diameter / 2, thickness / 2
    cap = round(thickness / diameter * 180 / math.pi, 2)
    sweep = 359.9 * value / maximum
    inset = min(cap, sweep / 4)
    tangent = half * math.tan(math.radians(inset)) / math.tan(math.radians(cap))
    start = paint_attribute(core, "startAngle", value, maximum)
    end = paint_attribute(core, "endAngle", value, maximum)
    def close(actual, expected):
        return math.isclose(actual, expected, rel_tol=0, abs_tol=1e-9)

    if not (close(start, 359.9 - sweep + inset) and close(end, 359.9 - inset)
            and end > start and end - start >= sweep / 2 - 1e-9):
        return False
    for group, endpoint in zip(mask.findall("Group"), (start, end)):
        ellipse = group.find("PartDraw/Ellipse")
        if ellipse is None:
            return False
        x = paint_attribute(ellipse, "x", value, maximum)
        b = paint_attribute(ellipse, "width", value, maximum) / 2
        if not (close(paint_attribute(group, "angle", value, maximum), endpoint)
                and close(x + b, 225) and close(b, tangent) and 0 < b <= half + 1e-9):
            return False
        # With b<=h<R the entire ellipse lies between R-h and R+h. Its
        # angular half-extent is not a linear scaling of the rounded c.
        extent = math.atan(b / math.sqrt(radius**2 - half**2))
        k = half / (math.sqrt(radius**2 - half**2) * math.tan(math.radians(cap)))
        error_bound = abs(k - 1) * math.tan(math.radians(inset))
        if (abs(extent - math.radians(inset)) > error_bound + 1e-12
                or math.degrees(2 * error_bound) > 0.04136
                or math.degrees(2 * error_bound) > sweep * 0.00151):
            return False
        if sweep >= 4 * cap and not (close(b, half) and close(inset, cap)):
            return False
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
        coverage = 1 if name.endswith("Half") else 0
        paint_diameter, paint_thickness = diameter + coverage, thickness + coverage
        groups = root.findall(f".//Group[@name='{name}']")
        if len(groups) != 1:
            errors.append(f"{name}: expected one owning band Group")
            continue
        group = groups[0]
        if group.attrib != {**canvas, "name": name, "alpha": "0"}:
            errors.append(f"{name}: band owner must retain initially hidden full-canvas coordinates")
        children = element_children(group)
        if not children or children[0].tag != "Transform":
            errors.append(f"{name}: geometry alpha must precede the unchanged drawings")
            continue
        children = children[1:]
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
        kinds = ["full", "tiny", "round"]
        for decision, kind in zip(decisions, kinds):
            name_kind = f"{name}_{kind}"
            if (decision.attrib != {**canvas, "name": name_kind, "alpha": "0"}
                    or [child.tag for child in element_children(decision)] != ["Transform", "PartDraw" if kind == "full" else "Group"]
                    or not check_paint_shape(decision[1], kind, paint_diameter, paint_thickness, name_kind, bool(coverage))):
                errors.append(f"{name_kind}: paint lost its isolated source/mask, endpoints, family or single ambient alpha")
        foreground = [node for child in children for node in child.iter()]
        if (sum(node.tag == "WeightedStroke" for node in foreground) != 3
                or sum(node.tag == "PartDraw" for node in foreground) != 10
                or sum(node.tag == "Stroke" for node in foreground) != 3
                or sum(node.tag == "Ellipse" for node in foreground) != 4):
            errors.append(f"{name}: paint escaped its three owning gates")

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
        paint_cap = round(paint_thickness / paint_diameter * 180 / math.pi, 2)
        cases += [(adjacent_float(4 * paint_cap / 359.9 * maximum, direction), "round") for direction in (-1, 1)]
        for value, wanted in cases:
            values = [evaluate_paint(alpha, value, maximum) for alpha in alphas]
            active = [kind for kind, alpha in zip(kinds, values) if alpha != 0]
            if any(alpha not in (0, 255) for alpha in values) or active != ([] if wanted == "none" else [wanted]):
                errors.append(f"{name}: {value}/{maximum} selected {active}, expected {wanted} alone")
            elif active:
                paint = decisions[kinds.index(wanted)][1]
                if not check_paint_endpoints(paint, wanted, paint_diameter, paint_thickness, value, maximum):
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
    lift = root.find("Scene/Group[@name='compositionChrome']/PartDraw[@name='lift']")
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
        "/Condition/Compare[@expression='isValid']/Group/Group[@name='ring1N1']"
    )
    if len(restores) != 1 or owner is None or element_children(owner)[1:2] != restores:
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


def check_main_decisions(root):
    """Evaluate every geometry gate; first-true selection must not hide overlaps."""
    errors = []
    canvas = {"x": "0", "y": "0", "width": "450", "height": "450"}
    ordinary = ("", "zero", "D", "7D", "M")
    paired = tuple(base + suffix for base in ("split", "split:cursor-other", "split:spark", "split:fable")
                   for suffix in ("", ":zero-inner", ":zero-outer", ":zero-both"))
    for index, slot_id in enumerate((101, 102, 105)):
        owner = root.find(f".//Group[@name='ring{index + 1}_main']")
        if owner is None:
            errors.append(f"slot {slot_id}: main geometry owner missing")
            continue
        groups = [group for group in owner.findall("Group")
                  if group.get("name") != f"ring{index + 1}_strip"]
        names = [group.get("name") for group in groups]
        expected = [f"ring{index + 1}{layout}{suffix}"
                    for layout, (_, _, diameters, _) in BAND_LAYOUTS.items() if index < len(diameters)
                    for suffix in ("Half", "")]
        if names != expected or any(group.attrib != {**canvas, "name": name, "alpha": "0"}
                                    for group, name in zip(groups, names)):
            errors.append(f"slot {slot_id}: expected stable paired/ordinary alpha Groups for each feasible layout")
            continue
        alphas = [alpha_expression(group) for group in groups]
        gate_errors = set()

        def selected(value, maximum, minimum=0, title=""):
            values = [evaluate_paint(alpha, value, maximum, minimum, title) for alpha in alphas]
            if any(alpha not in (0, 255) for alpha in values):
                gate_errors.add(f"slot {slot_id}: geometry alpha must be zero or 255")
            return [name for name, alpha in zip(names, values) if alpha != 0]

        # Geometry depends on envelope and TITLE, not on the foreground paint state.
        # Existing paint checks cover cutoff neighbors and proportional endpoints.
        for layout, (maximum, _, diameters, _) in BAND_LAYOUTS.items():
            for title in (*ordinary, *paired):
                suffix = "Half" if title in paired else ""
                wanted = [f"ring{index + 1}{layout}{suffix}"] if index < len(diameters) else []
                if any(selected(value, maximum, title=title) != wanted for value in (0, maximum)):
                    errors.append(f"slot {slot_id}/{layout}: {title!r} lost exclusive geometry admission")
            rejected = [(value, maximum, minimum, title) for value, minimum, title in (
                (-1, 0, ""), (maximum + 1, 0, "split:cursor-other"),
                (math.nan, 0, ""), (math.inf, 0, ""),
                (maximum, 1, ""), (maximum, math.nan, "split"),
                (maximum, 0, "credits"), (maximum, 0, "split:unknown"),
                (maximum, 0, "split:cursor-other:zero"), (maximum, 0, "split:spark:zero-both:extra"),
            )]
            if any(selected(value, upper, lower, title) for value, upper, lower, title in rejected):
                errors.append(f"slot {slot_id}/{layout}: malformed or credits-only input selected geometry")
        if any(selected(0, maximum) for maximum in (0, 50, 150, 300, 900, math.nan, math.inf)):
            errors.append(f"slot {slot_id}: unsupported envelope selected geometry")
        errors.extend(sorted(gate_errors))

    errors.extend(check_count_change_pair(root))
    # The focused declaration witness must detect ordinary overpaint and a missing
    # exact-full paired foreground, not merely the new selector's XML shape.
    for overlap in (False, True):
        broken = deepcopy(root)
        paired_gate = broken.find(".//Group[@name='ring1N2Half']/Transform")
        target = broken.find(".//Group[@name='ring1N2']/Transform" if overlap else
                             ".//Group[@name='ring1N2Half_full']/Transform")
        if paired_gate is None or target is None:
            errors.append("count-change counterexamples require the emitted geometry and full-paint gates")
            continue
        target.set("value", paired_gate.get("value") if overlap else "(0 == 1) ? 255 : 0")
        if not check_count_change_pair(broken):
            errors.append("overlapping ordinary geometry or suppressed paired full paint escaped the count-change regression")
    return errors


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
            tags = ["Transform", "PartDraw"] + ([] if kind == "zero" else ["PartDraw" if kind == "full" else "Group"])
            if [child.tag for child in children] != tags:
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
            if not check_paint_shape(paint, kind, diameter, thickness, name, paired=True):
                errors.append(f"{name}: selected drawing lost its isolated composition, geometry, family or ambient alpha")
            paints.append(paint)

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
                          adjacent_float(cutoff * maximum, 1),
                          adjacent_float(4 * cap / 359.9 * maximum, -1),
                          adjacent_float(4 * cap / 359.9 * maximum, 1), 0.37 * maximum, 0.99 * maximum,
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
                        paint = paints[positions[0]]
                        if not check_paint_endpoints(paint, kind, diameter, thickness / 2, value, maximum):
                            errors.append(f"slot {slot_id}/{layout}/{index}: selected {kind} endpoints or closure drifted")
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


def emitted_band_layers(root, responses, ambient=False):
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
            if ambient:
                variant = node.find("Variant[@mode='AMBIENT'][@target='alpha']")
                if variant is not None:
                    local_alpha = int(variant.get("value"))
            alpha = alpha * local_alpha / 255
            if alpha == 0:
                return
        if node.tag == "Group" and node.get("name") == N1_RESTORE:
            # Treat the isolated SOURCE/MASK result as backdrop, never a white track.
            mask = node.find("PartDraw[@renderMode='MASK']/Arc")
            if mask is not None:
                visit(mask, fields, "backdrop", alpha)
            return
        if node.tag == "Group" and node.get("name", "").endswith("_foreground"):
            # The source annulus supplies color only inside the mask union.
            # Keep one foreground layer, not an unmasked full-colored ring or
            # independently blended white/core/cap layers.
            mask = node.find("Group[@renderMode='MASK']")
            source = node.find("PartDraw[@renderMode='SOURCE']/Arc/WeightedStroke")
            if mask is not None and source is not None:
                core = mask.find("PartDraw/Arc")
                ellipse = mask.find("Group/PartDraw/Ellipse")
                # SOURCE allowance is not visible. The owning MASK defines the
                # ordinary/extra envelope or the bounded positive MAIN coverage.
                layers.append((float(core.get("width")) / 2, float(core.find("Stroke").get("thickness")),
                               paint_attribute(core, "startAngle", fields["value"], fields["maximum"]),
                               paint_attribute(core, "endAngle", fields["value"], fields["maximum"]),
                               ("ELLIPSE", paint_attribute(ellipse, "width", fields["value"], fields["maximum"]) / 2),
                               family, alpha, source.get("colors")))
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
        elif isinstance(cap, tuple) and cap[0] == "ELLIPSE":
            tangent = cap[1]
            if tangent > 0:
                inside |= any(((radius * math.cos(math.radians(angle - endpoint)) - center) / (thickness / 2))**2
                              + (radius * math.sin(math.radians(angle - endpoint)) / tangent)**2 <= 1
                              for endpoint in (start, end))
        if inside:
            if family == "track" and (alpha != 255 or color != "#ff2e3632"):
                raise ValueError("retained-extra protection requires the emitted opaque track")
            if family == "backdrop" and (alpha != 255 or color != "#ffffffff"):
                raise ValueError("backdrop restoration requires its opaque local mask")
            if family not in ("track", "backdrop") and color != "[COMPLICATION.RANGED_VALUE_COLORS]":
                raise ValueError("family ownership lost its response color source")
            owner = family
    return owner


def check_count_change_pair(root):
    """Source-projected Cursor100/Other64.1 declarations, not retained native state."""
    errors = []
    remaining = struct.unpack("!f", struct.pack("!f", 100 - 35.9))[0]
    main = root.find(".//Group[@name='ring1_main']")
    extra = root.find(".//ComplicationSlot[@slotId='106']/Complication[@type='RANGED_VALUE']")
    if main is None or extra is None:
        return ["count-change pair requires its independent main and extra consumers"]
    main_groups = [group for group in main.findall("Group") if group.get("name") != "ring1_strip"]
    extra_groups = [group for group in extra.findall("Group")
                    if group.get("name", "").startswith("outerHalf106_")]

    def response(value, maximum, title, family):
        return ({"value": value, "maximum": maximum, "minimum": 0, "title": title}, family)

    def selected(groups, fields):
        return [group.get("name") for group in groups
                if evaluate_paint(alpha_expression(group), **fields) != 0]

    for layout, maximum, inner_edges, outer_edges in (
        ("N3", 800, (182, 193), (192, 202)),
        ("N2", 400, (170, 187), (186, 202)),
    ):
        state = {101: response(maximum, maximum, "split:cursor-other", "Cursor"),
                 106: response(remaining * (maximum / 100), maximum, "0", "Other")}
        if (selected(main_groups, state[101][0]) != [f"ring1{layout}Half"]
                or selected(extra_groups, state[106][0]) != [f"outerHalf106_{layout}_1_round"]):
            errors.append(f"{layout} Cursor100/Other64.1 must activate only its current paired geometry")
        layers = emitted_band_layers(root, state)
        for family, edges in (("Cursor", inner_edges), ("Other", outer_edges)):
            paints = [layer for layer in layers if layer[5] == family]
            if len(paints) != 1:
                errors.append(f"{layout}: {family} must retain one independent foreground")
                continue
            center, thickness, start, end, cap, _, alpha, color = paints[0]
            if ((center - thickness / 2, center + thickness / 2) != edges
                    or alpha != 255 or color != "[COMPLICATION.RANGED_VALUE_COLORS]"
                    or (family == "Cursor" and (start, end, cap) != (0, 359.9, "ROUND"))):
                errors.append(f"{layout}: {family} lost its intended half-width/full-main declaration")
            if visible_band_owner(layers, sum(edges) / 2, 300) != family:
                errors.append(f"{layout}: {family} is covered by another geometry")
        if visible_band_owner(layers, sum(outer_edges) / 2, 90) != "track":
            errors.append(f"{layout}: full main must not fill the extra's spent region")

    ordinary = response(400, 400, "", "Cursor")
    layers = emitted_band_layers(root, {101: ordinary})
    paints = [layer for layer in layers if layer[5] == "Cursor"]
    if (selected(main_groups, ordinary[0]) != ["ring1N2"] or len(paints) != 1
            or paints[0][:5] != (186, 32, 0, 359.9, "ROUND")):
        errors.append("ordinary full N2 must occupy its whole 170..202 band, unlike the paired full main")
    return errors


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

                # Positive MAIN owns the bounded overlap, even beside a zero or
                # absent extra. These are declaration/alpha checks, not AA proof.
                half = BAND_LAYOUTS[layout][1] / 2
                join = (inner + half) / 2
                for ambient in (False, True):
                    for fraction in (0, 0.37, 1):
                        main_response = response(maximum * fraction, maximum, "split:cursor-other", "Cursor")
                        paired = {main_id: main_response,
                                  slot_id: response(maximum, maximum, str(index), "Other")}
                        layers = emitted_band_layers(root, paired, ambient)
                        main_paints = [layer for layer in layers if layer[5] == "Cursor"]
                        extra_paints = [layer for layer in layers if layer[5] == "Other"]
                        expected_alpha = 140 if ambient else 255
                        if (len(main_paints) != (0 if fraction == 0 else 1) or len(extra_paints) != 1
                                or extra_paints[0][:2] != (outer / 2, half)
                                or any(layer[6] != expected_alpha for layer in main_paints + extra_paints)
                                or (main_paints and main_paints[0][:2] != ((inner + 1) / 2, half + 1))):
                            errors.append(f"{label}: positive coverage/extra role or single ambient alpha drifted")
                        if (visible_band_owner(layers, join + 0.5, 300) != ("Cursor" if fraction else "Other")
                                or visible_band_owner(layers, join + 1.5, 300) != "Other"):
                            errors.append(f"{label}: MAIN must cover exactly one reference unit of the shared edge")
                        if fraction:
                            for peer in (None, response(0, maximum, str(index), "Other")):
                                state = {main_id: main_response}
                                if peer is not None:
                                    state[slot_id] = peer
                                own_layers = emitted_band_layers(root, state, ambient)
                                if (visible_band_owner(own_layers, join + 0.5, 300) != "Cursor"
                                        or any(layer[5] == "Other" for layer in own_layers)):
                                    errors.append(f"{label}: own positive coverage invented or depended on peer foreground")

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
            extent = (math.degrees(math.atan(cap[1] / math.sqrt(center**2 - (thickness / 2)**2)))
                      if isinstance(cap, tuple) else math.nan)
            visible = end - start + 2 * extent
            calibration_error = 2 * (math.degrees(math.asin(11.5 / 169.5)) - round(23 / 339 * 180 / math.pi, 2))
            if ((center, thickness, alpha, color)
                    != (169.5, 23, 255, "[COMPLICATION.RANGED_VALUE_COLORS]")
                    or not isinstance(cap, tuple) or not math.isclose(cap[1], 11.5, rel_tol=0, abs_tol=1e-9)
                    or not math.isclose(visible, main_value / 200 * 359.9 + calibration_error, rel_tol=0, abs_tol=1e-9)):
                errors.append(f"{label}: Float projection lost the calibrated ordinary ROUND silhouette")
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
    # Reject nominal MAIN paint, misplaced SOURCE/MASK coverage, double
    # attenuation and a constant tiny-cap floor without weakening other roles.
    for target, attribute, value in (
        (".//Group[@name='ring1N1Half_full']/PartDraw/Arc", "width", "338"),
        (".//Group[@name='ring1N1Half_round_foreground']/PartDraw/Arc", "width", "338"),
        (".//Group[@name='ring1N1Half_round_mask']/PartDraw/Arc/Stroke", "thickness", "22"),
        (".//Group[@name='ring1N1Half_full']/PartDraw/Variant", "value", "255"),
        (".//Group[@name='ring1N1Half_round_mask']", "renderMode", "ALL"),
        (".//Group[@name='ring1N1Half_round_mask']", "alpha", "140"),
        (".//Group[@name='ring1N1Half_tiny_startCap']/PartDraw/Ellipse/Transform[@target='width']", "value", "22"),
    ):
        broken = deepcopy(root)
        node = broken.find(target)
        if node is None:
            errors.append("partial-mask counterexample requires its emitted owning node")
            continue
        node.set(attribute, value)
        if not check_band_paints(broken):
            errors.append("escaped/attenuated mask or cap floor no longer fails paint coverage")
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
        wanted = ["Transform", "PartDraw"] + ([] if kind == "zero" else ["PartDraw" if kind == "full" else "Group"]) + ["Group"]
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
    print("watchface condition trees, temperature semantics, alpha gates and drawing containment passed")


if __name__ == "__main__":
    main()
