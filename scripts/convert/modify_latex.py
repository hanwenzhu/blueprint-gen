import re
from pathlib import Path

from loguru import logger

from common import Node, NodeWithPos

def convert_latex_label_to_lean_name(source: str, label_to_node: dict[str, Node]) -> str:
    r"""Convert latex-label-of-node to lean_name_of_node if possible in \ref and \uses commands."""
    def replace_ref(match):
        command = match.group(1)
        labels = [label.strip() for label in match.group(2).split(",")]
        labels = [label_to_node[label].name if label in label_to_node else label for label in labels]
        return f"\\{command}{{{', '.join(labels)}}}"
    ref_commands = [
        # From https://github.com/jgm/pandoc/blob/main/src/Text/Pandoc/Readers/LaTeX/Inline.hs
        "ref", "cref", "Cref", "vref", "eqref", "autoref",
        # Blueprint \uses
        "uses"
    ]
    soruce = re.sub(r"\\(" + "|".join(ref_commands) + r")\s*\{([^\}]*)\}", replace_ref, source)
    soruce = soruce.strip()
    return soruce

def write_latex_source(
    nodes_with_pos: list[NodeWithPos],
    name_to_raw_latex_sources: dict[str, list[str]],
    label_to_node: dict[str, Node],
    blueprint_root: Path,
    convert_informal: bool,
    libraries: list[str]
):
    # Convert nodes to \inputleannode
    name_to_node_with_pos = {node.name: node for node in nodes_with_pos}
    for name, raw_latex_sources in name_to_raw_latex_sources.items():
        if name not in name_to_node_with_pos:
            logger.warning(f"Node {name} not found in nodes_with_pos")
            continue
        # If not convert_informal, skip writing \inputleannode for nodes that are not in Lean
        if not convert_informal and not name_to_node_with_pos[name].has_lean:
            continue
        first_source, *rest_sources = raw_latex_sources
        for file in blueprint_root.glob("**/*.tex"):
            file_content = file.read_text()
            file_content = file_content.replace(first_source, f"\\inputleannode{{{name}}}")
            for s in rest_sources:
                file_content = file_content.replace(s, "")
            file.write_text(file_content)

    # Convert existing \ref and \uses commands
    for file in blueprint_root.glob("**/*.tex"):
        file_content = file.read_text()
        file_content = convert_latex_label_to_lean_name(file_content, label_to_node)
        file.write_text(file_content)

    # Add import to macros file
    macros_file = blueprint_root / "macros" / "common.tex"
    new_macros = "\n".join(f"\\input{{../../.lake/build/blueprint/library/{library}}}" for library in libraries)
    if macros_file.exists():
        macros = macros_file.read_text()
        macros += "\n" + new_macros + "\n"
        macros_file.write_text(macros)
    else:
        logger.warning(f"{macros_file} not found; please add the following to anywhere in the start of LaTeX blueprint:\n{new_macros}")
