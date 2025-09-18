import argparse
import json
from pathlib import Path
import subprocess

import loguru

from common import Node, NodeWithPos, convert_node_latex_to_markdown
from parse_latex import parse_blueprint_file, parse_dep_graph


def main():
    parser = argparse.ArgumentParser(description="Convert existing leanblueprint file to blueprint-gen format.")
    parser.add_argument(
        "--imports",
        nargs="+",
        required=True,
        help="Lean modules to import.",
    )
    parser.add_argument(
        "--blueprint_root",
        type=str,
        default=None,
        help="Path to the blueprint root directory, which should contain web.tex and plastex.cfg (default: blueprint/src or blueprint).",
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

    # Parse blueprint file into TeXDocument
    loguru.logger.info(f"Parsing blueprint file {blueprint_root / 'web.tex'}")
    document = parse_blueprint_file(blueprint_root)

    # Parse the document into nodes in dependency graph
    loguru.logger.info("Parsing dependency graph")
    nodes = parse_dep_graph(document)

    # Convert LaTeX to Markdown
    loguru.logger.info("Converting LaTeX to Markdown using Pandoc")
    for node in nodes:
        convert_node_latex_to_markdown(node)

    # Convert nodes to JSON
    loguru.logger.info("Converting nodes to JSON")
    nodes_json = json.dumps(
        [node.model_dump(mode="json", by_alias=True) for node in nodes],
        ensure_ascii=False
    )

    # Add position information to nodes by passing to a Lean script
    loguru.logger.info("Adding position information to nodes using `lake exe add_position_info`")
    nodes_with_pos_json = subprocess.run(
        ["lake", "exe", "add_position_info", "--imports", ",".join(args.imports)],
        input=nodes_json,
        capture_output=True,
        text=True,
        check=True
    ).stdout

    # Parse the JSON into NodeWithPos
    loguru.logger.info("Parsing JSON into NodeWithPos")
    nodes_with_pos = [
        NodeWithPos.model_validate(node) for node in json.loads(nodes_with_pos_json)
    ]

    for node in nodes_with_pos:
        print(node)


if __name__ == "__main__":
    main()
