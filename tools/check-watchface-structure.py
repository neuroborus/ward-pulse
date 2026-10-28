#!/usr/bin/env python3
"""Check WFF condition trees in the generator's actual XML on stdin."""

import sys
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


def main():
    parser = ET.XMLParser(target=ET.TreeBuilder(insert_comments=True))
    root = ET.parse(sys.stdin, parser=parser).getroot()
    errors = check_structure(root)
    if errors:
        sys.exit("\n".join(errors))
    print("watchface condition trees and main selector/strip containment passed")


if __name__ == "__main__":
    main()
