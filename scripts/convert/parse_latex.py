import uuid
from pathlib import Path
import re
from dataclasses import dataclass
from typing import Optional

from loguru import logger

from common import Node, NodePart


def read_latex_file(file: Path) -> str:
    """Read the LaTeX file at `file`, recursively resolving and inlining any `\\input{...}` commands."""
    root_dir = file.parent
    def _read(file: Path, seen: set[Path]) -> str:
        if file in seen:
            logger.warning(f"Circular \\input detected for file: {file}")
            return ""
        seen.add(file)
        text = file.read_text()
        def replace_input(match):
            input_path = match.group(1).strip()
            if not input_path.endswith(".tex"):
                input_path += ".tex"
            input_file : Path = root_dir / input_path
            if not input_file.exists():
                logger.warning(f"\\input file not found: {input_file}")
                return ""
            return _read(input_file, seen)
        text = re.sub(r"\\input\s*\{([^\}]*)\}", replace_input, text)
        return text
    return _read(file, set())


def find_and_remove_command(command: str, source: str) -> tuple[bool, str]:
    match = re.search(r"\\" + command + r"\b", source)
    source = re.sub(r"\\" + command + r"\b", "", source)
    return match is not None, source


def find_and_remove_command_arguments(command: str, source: str, sub_count: int = 0) -> tuple[list[str], str]:
    matches = re.findall(r"\\" + command + r"\s*\{([^\}]*)\}", source)
    values = [item.strip() for m in matches for item in m.split(",")]
    source = re.sub(r"\\" + command + r"\s*\{[^\}]*\}", "", source, count=sub_count)
    return values, source


def find_and_remove_command_argument(command: str, source: str) -> tuple[Optional[str], str]:
    args, source = find_and_remove_command_arguments(command, source, sub_count=1)
    if len(args) > 1:
        logger.warning(f"Multiple \\{command} arguments found: {args}; only using the first one.")
    return args[0] if args else None, source


@dataclass
class SourceInfo:
    label: Optional[str]
    uses: list[str]
    alsoIn: list[str]
    proves: Optional[str]
    leanok: bool
    notready: bool
    mathlibok: bool
    lean: Optional[str]
    discussion: Optional[int]


def parse_and_remove_blueprint_commands(source: str) -> tuple[SourceInfo, str]:
    """Parse and remove custom commands (\\label, plastexdepgraph, leanblueprint commands)."""
    # \label
    label, source = find_and_remove_command_argument("label", source)
    # plastexdepgraph commands
    uses, source = find_and_remove_command_arguments("uses", source)
    alsoIn, source = find_and_remove_command_arguments("alsoIn", source)
    proves, source = find_and_remove_command_argument("proves", source)
    # leanblueprint commands
    leanok, source = find_and_remove_command("leanok", source)
    notready, source = find_and_remove_command("notready", source)
    mathlibok, source = find_and_remove_command("mathlibok", source)
    lean, source = find_and_remove_command_argument("lean", source)
    discussion, source = find_and_remove_command_argument("discussion", source)
    source = source.strip()
    return SourceInfo(
        label=label,
        uses=uses,
        alsoIn=alsoIn,
        proves=proves,
        leanok=leanok,
        notready=notready,
        mathlibok=mathlibok,
        lean=lean,
        discussion=try_int(discussion)
    ), source


def try_int(s: Optional[str]) -> Optional[int]:
    if s is None:
        return None
    try:
        return int(s)
    except ValueError:
        return None


def convert_ref_to_texttt(source: str, label_to_node: dict[str, Node]):
    r"""Convert \ref{abc} to \texttt{abc}.

    This is so that in the output, [\[long_theorem_name\]](#long_theorem_name) becomes
    `long_theorem_name` instead, and the latter can be automatically converted to
    links/refs by both doc-gen4 and blueprint-gen.
    """
    def replace_ref(match):
        label = match.group(1)
        if label not in label_to_node:
            if "_" in label:
                # If the label contains an underscore, we assume it is still a Lean name and wrap it in \texttt,
                # even though it is not in the blueprint graph.
                return f"\\texttt{{{label}}}"
            else:
                return match.group(0)
        return f"\\texttt{{{label_to_node[label].name}}}"
    source = re.sub(r"\\ref\s*\{([^\}]*)\}", replace_ref, source)
    source = source.strip()
    return source


def convert_latex_label_to_lean_name(node_part: NodePart, label_to_node: dict[str, Node]):
    """Converts the `uses` and `\\ref` commands to reference Lean names rather than LaTeX labels."""
    for use in list(node_part.uses_raw):
        if use in label_to_node:
            # Convert from LaTeX labels in uses_raw to Lean names in uses, if the used node is formalized
            used_node = label_to_node[use]
            if used_node.statement.lean_ok:
                node_part.uses_raw.remove(use)
                node_part.uses.add(used_node.name)
        else:
            logger.warning(f"\\uses {use} label not found")
    node_part.text = convert_ref_to_texttt(node_part.text, label_to_node)


def remove_nonbreaking_spaces(source: str) -> str:
    source = re.sub(r"(?<!\\)~", r" ", source)
    source = source.strip()
    return source


def process_source(source: str) -> tuple[SourceInfo, str]:
    """Returns the source TeX of the node, removing custom commands."""
    source = remove_nonbreaking_spaces(source)
    return parse_and_remove_blueprint_commands(source)


# NB: this is essentially not used if --convert_informal is not set
def generate_new_lean_name(visited_names: set[str], base: Optional[str]) -> str:
    """Generate a unique Lean identifier."""
    if base is None:
        base = f"node_{uuid.uuid4().hex}"
    else:
        base = base.split(":")[-1].replace("-", "_").replace(" ", "_")
        if base and base[0].isdigit():
            base = "_" + base
    if base not in visited_names:
        return base
    return generate_new_lean_name(visited_names, f"{base}_{uuid.uuid4().hex}")


def parse_nodes(source: str) -> tuple[list[Node], dict[str, list[str]]]:
    """Parse the nodes in the LaTeX source."""
    match = re.search(r"\\usepackage\s*\[[^\]]*\bthms\s*=\s*([^,\]\}]*)", source)
    if match:
        depgraph_thm_types = match.group(1).strip().split("+")
    else:
        depgraph_thm_types = "definition+lemma+proposition+theorem+corollary".split("+")

    ENV_PATTERN = re.compile(
        r"\\begin\s*\{(" + "|".join(depgraph_thm_types + ["proof"]) + r")\}\s*(?:\[(.*?)\])?(.*?)\\end\s*\{\1\}",
        re.DOTALL
    )

    # Maps matches[i] to node
    match_idx_to_node: dict[int, Node] = {}

    # Parsed nodes
    nodes: list[Node] = []
    name_to_node: dict[str, Node] = {}
    label_to_node: dict[str, Node] = {}

    # Raw sources of each name, for modifying LaTeX later
    name_to_raw_sources: dict[str, list[str]] = {}

    # Parse all theorem and definition statements
    for i, match in enumerate(ENV_PATTERN.finditer(source)):
        env, title, content = match.groups()

        if env not in depgraph_thm_types:
            continue

        source_info, node_source = process_source(content)
        name = source_info.lean or generate_new_lean_name(set(name_to_node.keys()), source_info.label)
        name_to_raw_sources.setdefault(name, []).append(match.group(0))

        if name in name_to_node:
            logger.warning(f"Lean name {name} occurs in blueprint twice; only keeping the first.")
            node = name_to_node[name]
        else:
            statement = NodePart(
                lean_ok=source_info.leanok, text=node_source,
                uses=set(), uses_raw=set(source_info.uses),  # to be converted in the next loop
                latex_env=env
            )
            node = Node(name=name, statement=statement, proof=None, not_ready=source_info.notready, discussion=source_info.discussion, title=title)
            nodes.append(node)
            name_to_node[name] = node

        match_idx_to_node[i] = node
        if source_info.label is not None:
            label_to_node[source_info.label] = node

    # Parse all proof statements
    for i, match in enumerate(ENV_PATTERN.finditer(source)):
        env, title, content = match.groups()

        if env != "proof":
            continue

        source_info, node_source = process_source(content)
        proves = source_info.proves
        if proves is not None:
            proved = label_to_node[proves]
        else:
            if i - 1 in match_idx_to_node:
                proved = match_idx_to_node[i - 1]
            else:
                logger.warning(f"Cannot determine the statement proved by: {node_source}")
                continue

        proved.proof = NodePart(
            lean_ok=source_info.leanok, text=node_source,
            uses=set(), uses_raw=set(source_info.uses),  # to be converted in the next loop
            latex_env=env
        )
        name_to_raw_sources.setdefault(proved.name, []).append(match.group(0))

    # Convert node \label to node.name
    for node in nodes:
        convert_latex_label_to_lean_name(node.statement, label_to_node)
        if node.proof is not None:
            convert_latex_label_to_lean_name(node.proof, label_to_node)

    return nodes, name_to_raw_sources


def get_bibliography_files(source: str) -> list[Path]:
    """Get the bibliography from the document."""
    bibs, _ = find_and_remove_command_arguments("bibliography", source)
    bibs = [Path(bib + ".bib") for bib in bibs]
    return bibs
