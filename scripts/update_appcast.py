#!/usr/bin/env python3

import argparse
import os
import xml.etree.ElementTree as ET

SPARKLE_NS = "http://www.andymatuschak.org/xml-namespaces/sparkle"

ET.register_namespace("sparkle", SPARKLE_NS)


def indent(element, level=0):
    indentation = "\n" + level * "    "
    if len(element):
        if not element.text or not element.text.strip():
            element.text = indentation + "    "
        for child in element:
            indent(child, level + 1)
        if not child.tail or not child.tail.strip():
            child.tail = indentation
    if level and (not element.tail or not element.tail.strip()):
        element.tail = indentation


def load_or_create_appcast(path, title, link, description, language):
    if os.path.exists(path):
        tree = ET.parse(path)
        root = tree.getroot()
        channel = root.find("channel")
        if channel is None:
            channel = ET.SubElement(root, "channel")
        return tree, root, channel

    root = ET.Element(
        "rss",
        {
            "version": "2.0",
            "xmlns:sparkle": SPARKLE_NS,
        },
    )
    channel = ET.SubElement(root, "channel")
    ET.SubElement(channel, "title").text = title
    ET.SubElement(channel, "link").text = link
    ET.SubElement(channel, "description").text = description
    ET.SubElement(channel, "language").text = language
    return ET.ElementTree(root), root, channel


def ensure_channel_metadata(channel, title, link, description, language):
    def get_or_create(tag, value):
        existing = channel.find(tag)
        if existing is None:
            existing = ET.SubElement(channel, tag)
        existing.text = value
        return existing

    return [
        get_or_create("title", title),
        get_or_create("link", link),
        get_or_create("description", description),
        get_or_create("language", language),
    ]


def remove_existing_item(channel, sparkle_version, enclosure_url):
    for item in list(channel.findall("item")):
        enclosure = item.find("enclosure")
        if enclosure is None:
            continue
        existing_version = enclosure.get(f"{{{SPARKLE_NS}}}version")
        existing_url = enclosure.get("url")
        if existing_version == sparkle_version or existing_url == enclosure_url:
            channel.remove(item)


def main():
    parser = argparse.ArgumentParser(
        description="Update a Sparkle appcast with a Book Sender release."
    )
    parser.add_argument("--appcast", required=True)
    parser.add_argument("--title", required=True)
    parser.add_argument("--link", required=True)
    parser.add_argument("--description", required=True)
    parser.add_argument("--language", default="en")
    parser.add_argument("--version", required=True)
    parser.add_argument("--short-version", required=True)
    parser.add_argument("--minimum-system-version", required=True)
    parser.add_argument("--pub-date", required=True)
    parser.add_argument("--enclosure-url", required=True)
    parser.add_argument("--enclosure-length", required=True)
    parser.add_argument("--ed-signature", required=True)
    parser.add_argument("--release-notes", default="")
    args = parser.parse_args()

    tree, root, channel = load_or_create_appcast(
        args.appcast,
        args.title,
        args.link,
        args.description,
        args.language,
    )
    metadata_nodes = ensure_channel_metadata(
        channel,
        args.title,
        args.link,
        args.description,
        args.language,
    )
    remove_existing_item(channel, args.version, args.enclosure_url)

    item = ET.Element("item")
    ET.SubElement(item, "title").text = f"Version {args.short_version}"
    ET.SubElement(item, "pubDate").text = args.pub_date
    minimum_version = ET.SubElement(
        item,
        f"{{{SPARKLE_NS}}}minimumSystemVersion",
    )
    minimum_version.text = args.minimum_system_version

    enclosure = ET.SubElement(item, "enclosure")
    enclosure.set("url", args.enclosure_url)
    enclosure.set(f"{{{SPARKLE_NS}}}version", args.version)
    enclosure.set(
        f"{{{SPARKLE_NS}}}shortVersionString",
        args.short_version,
    )
    enclosure.set(f"{{{SPARKLE_NS}}}edSignature", args.ed_signature)
    enclosure.set(f"{{{SPARKLE_NS}}}os", "macos")
    enclosure.set("length", str(args.enclosure_length))
    enclosure.set("type", "application/zip")

    if args.release_notes:
        ET.SubElement(item, "description").text = args.release_notes

    children = list(channel)
    existing_items = [child for child in children if child.tag == "item"]
    other_nodes = [
        child
        for child in children
        if child.tag not in {"title", "link", "description", "language", "item"}
    ]

    for child in children:
        channel.remove(child)
    for node in metadata_nodes:
        channel.append(node)
    for node in other_nodes:
        channel.append(node)
    channel.append(item)
    for existing_item in existing_items:
        channel.append(existing_item)

    indent(root)
    tree.write(args.appcast, encoding="utf-8", xml_declaration=True)


if __name__ == "__main__":
    main()
