import argparse
import json
from pathlib import Path
import subprocess
import sys

from loguru import logger

from common import Node, NodeWithPos, convert_node_latex_to_markdown
from parse_latex import read_latex_file, parse_nodes, get_bibliography_files
from modify_lean import write_blueprint_attributes


def main():
    parser = argparse.ArgumentParser(description="Convert existing leanblueprint file to blueprint-gen format.")
    parser.add_argument(
        "--modules",
        nargs="+",
        required=True,
        help="The names of Lean modules for conversion. " +
             "The blueprint nodes are assumed to be accessible from these modules, " +
             "and their (sub)modules will be modified to add @[blueprint] attributes.",
    )
    parser.add_argument(
        "--blueprint_root",
        type=str,
        default=None,
        help="Path to the blueprint root directory, which should contain web.tex and plastex.cfg (default: blueprint/src or blueprint).",
    )
    parser.add_argument(
        "--extract-only",
        action="store_true",
        help="Only extract the nodes and print them to stdout in JSON; no modification is made to the Lean source.",
    )

    args = parser.parse_args()

    # Determine blueprint root directory
    if args.blueprint_root is None:
        blueprint_root = Path("blueprint/src")
        if not (blueprint_root / "web.tex").exists():
            blueprint_root = Path("blueprint")
            if not (blueprint_root / "web.tex").exists():
                raise FileNotFoundError("web.tex not found in blueprint or blueprint/src")
        blueprint_root = Path(blueprint_root)
    else:
        blueprint_root = Path(args.blueprint_root)

    # Read the blueprint LaTeX file
    logger.info(f"Reading blueprint LaTeX file {blueprint_root / 'web.tex'}")
    source = read_latex_file(blueprint_root / "web.tex")

    # Parse the document into nodes in dependency graph
    logger.info("Parsing nodes in blueprint LaTeX")
    nodes, name_to_raw_latex_sources = parse_nodes(source)

    # Convert nodes to JSON
    logger.info("Converting nodes to JSON")
    nodes_json = json.dumps(
        [node.model_dump(mode="json", by_alias=True) for node in nodes],
        ensure_ascii=False
    )

    # Add position information to nodes by passing to a Lean script
    logger.info("Adding position information to nodes using `lake exe add_position_info`")
    nodes_with_pos_json = subprocess.run(
        ["lake", "exe", "add_position_info", "--imports", ",".join(args.modules)],
        input=nodes_json,
        text=True,
        check=True,
        stdout=subprocess.PIPE,
        stderr=sys.stderr,
    ).stdout

    if args.extract_only:
        print(nodes_with_pos_json)
        return

    # Parse the JSON into NodeWithPos
    logger.info("Parsing JSON into NodeWithPos")
    nodes_with_pos = [
        NodeWithPos.model_validate(node) for node in json.loads(nodes_with_pos_json)
    ]

    # Convert LaTeX to Markdown
    logger.info("Converting LaTeX to Markdown using Pandoc")
    for node in nodes_with_pos:
        convert_node_latex_to_markdown(node)

    # Write the blueprint attributes to Lean files
    logger.info("Writing @[blueprint] attributes to Lean files")
    write_blueprint_attributes(nodes_with_pos, args.modules)

    # Write to LaTeX source
    logger.info("Replacing LaTeX theorems with \\inputleannode")
    name_to_node_with_pos = {node.name: node for node in nodes_with_pos}
    for name, raw_latex_sources in name_to_raw_latex_sources.items():
        if name not in name_to_node_with_pos:
            logger.warning(f"Node {name} not found in nodes_with_pos")
            continue
        # # Skip writing \inputleannode for nodes that are not in Lean
        # if not name_to_node_with_pos[name].has_lean:
        #     continue
        first_source, *rest_sources = raw_latex_sources
        for file in blueprint_root.glob("**/*.tex"):
            file_content = file.read_text()
            file_content = file_content.replace(first_source, f"\\inputleannode{{{name}}}")
            for s in rest_sources:
                file_content = file_content.replace(s, "")
            file.write_text(file_content)


if __name__ == "__main__":
    main()
