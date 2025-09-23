import uuid
from pathlib import Path
import re

from loguru import logger

import leanblueprint.Packages.blueprint as blueprint
import plastexdepgraph.Packages.depgraph as depgraph
from plasTeX.Base.LaTeX.Crossref import label, ref
from plasTeX.TeX import TeX, Macro
from plasTeX import TeXDocument, Environment
from plasTeX.Config import defaultConfig

from common import Node, NodePart


def parse_blueprint_file(blueprint_root: Path) -> TeXDocument:
    """Parse the blueprint file and return the plasTeX document."""
    config = defaultConfig()
    config_file = blueprint_root / "plastex.cfg"
    if not config_file.exists():
        raise FileNotFoundError(f"{config_file} not found")
    config.read(str(config_file))
    document = TeXDocument(config=config)
    document.setUserData("jobname", "parse-blueprint")
    document.setUserData("working-dir", blueprint_root)
    tex = TeX(ownerDocument=document, file=str(blueprint_root / "web.tex"))
    tex.parse()
    return document


def is_blueprint_command(node: Macro) -> bool:
    """If node is a custom command defined in plastexdepgraph or leanblueprint, or a \\label command."""
    if isinstance(node, label):
        return True
    for cls in node.__class__.__mro__:
        if cls.__module__.startswith("plastexdepgraph") or cls.__module__.startswith("leanblueprint"):
            return True
    return False


def clear_blueprint_commands(node: Macro):
    """Recursively remove custom commands (defined by is_blueprint_command) from the node."""
    for child in list(node.childNodes):
        if is_blueprint_command(child):
            node.removeChild(child)
        else:
            clear_blueprint_commands(child)


def convert_ref_to_texttt(node: Macro):
    r"""Convert \ref{abc} to \texttt{abc}.

    This is so that in the output, [\[long_theorem_name\]](#long_theorem_name) becomes
    `long_theorem_name`, and the latter can be automatically converted to links/refs by both
    doc-gen4 and blueprint-gen.
    """
    from plasTeX.Base.LaTeX.FontSelection import texttt
    for child in list(node.childNodes):
        if isinstance(child, ref):
            new_child = texttt()
            new_child.argSource = child.argSource
            node.replaceChild(new_child, child)
        else:
            convert_ref_to_texttt(child)


def remove_unnecessary_spaces(source: str) -> str:
    """
    Removes unnecessary spaces generated from LaTeX source.
    (See https://github.com/plastex/plastex/issues/313).
    """
    # NB: The `(?<!\\)` is to avoid replacing escaped `\`
    # Replace `\# a` with `\#a`
    source = re.sub(r"(?<!\\)(\\[^a-zA-Z]) ", r"\1", source)
    # Replace `\a _b` with `\a_b`
    source = re.sub(r"(?<!\\)(\\[a-zA-Z]+) (?=[^a-zA-Z])", r"\1", source)
    # Replace ~ with space, since we don't have this in Markdown
    source = re.sub(r"(?<!\\)~", r" ", source)
    source = source.strip()
    return source


def process_source(node: Macro) -> str:
    """Returns the source TeX of the node, removing custom commands."""
    clear_blueprint_commands(node)
    convert_ref_to_texttt(node)
    return remove_unnecessary_spaces(node.childrenSource)


def try_int(s: str | None) -> int | None:
    if s is None:
        return None
    try:
        return int(s)
    except ValueError:
        return None


def generate_new_lean_name(visited_names: set[str], base: str | None) -> str:
    """Generate a unique Lean identifier."""
    if base is None:
        base = f"node_{uuid.uuid4().hex}"
    else:
        base = base.replace("-", "_")
    if base not in visited_names:
        return base
    return generate_new_lean_name(visited_names, f"{base}_{uuid.uuid4().hex}")


def parse_dep_graph(document: TeXDocument) -> list[Node]:
    """Parse the dependency graph."""
    graphs: list[depgraph.DepGraph] = list(document.userdata["dep_graph"]["graphs"].values())

    proof_env: Environment

    # Resulting Nodes
    env_to_node: dict[Environment, Node] = {}
    nodes: list[Node] = []
    name_to_node: dict[str, Node] = {}

    # First pass: collect nodes
    for graph in graphs:
        for node_env in graph.nodes:
            node_env: Environment

            lean_decls: list[str] = node_env.userdata.get("leandecls", [])
            if len(lean_decls) > 1:
                logger.warning(f"Multiple Lean names found for {node_env.id}: {lean_decls}; only using the first one.")
            name: str = lean_decls[0] if lean_decls else generate_new_lean_name(set(name_to_node.keys()), node_env.id)
            # has_lean = len(lean_decls) > 0

            if name in name_to_node:
                logger.warning(f"Lean name {name} occurs in blueprint twice; only keeping the first.")
                env_to_node[node_env] = name_to_node[name]
                if "proved_by" in node_env.userdata:
                    proof_env = node_env.userdata["proved_by"]
                    env_to_node[proof_env] = name_to_node[name]
                continue

            statement = NodePart(lean_ok=node_env.userdata.get("leanok", False), text=process_source(node_env), uses=set(), latex_env=node_env.tagName)

            not_ready = node_env.userdata.get("notready", False)
            discussion = try_int(node_env.userdata.get("issue", None))
            title = node_env.title.source if node_env.title is not None else None
            node = Node(
                name=name, statement=statement, proof=None,
                not_ready=not_ready, discussion=discussion, title=title
            )
            name_to_node[name] = node
            env_to_node[node_env] = node
            nodes.append(node)

            if "proved_by" in node_env.userdata:
                proof_env = node_env.userdata["proved_by"]
                proof = NodePart(lean_ok=proof_env.userdata.get("leanok", False), text=process_source(proof_env), uses=set(), latex_env=proof_env.tagName)
                node.proof = proof
                env_to_node[proof_env] = node

    # Second pass: collect \uses dependencies
    for graph in graphs:
        for node_env in graph.nodes:
            if node_env not in env_to_node:
                continue
            node = env_to_node[node_env]
            for use in node_env.userdata.get("uses", []):
                if use in env_to_node:
                    node.statement.uses.add(env_to_node[use].name)
                else:
                    logger.warning(f"\\uses {use.id} not found in dependency graph")
            if node.proof is not None:
                proof_env = node_env.userdata["proved_by"]
                for use in proof_env.userdata.get("uses", []):
                    if use in env_to_node:
                        node.proof.uses.add(env_to_node[use].name)
                    else:
                        logger.warning(f"\\uses {use.id} not found in dependency graph")

    return nodes


def get_bibliography_files(document: TeXDocument) -> list[Path]:
    """Get the bibliography from the document."""
    from plasTeX.Base.LaTeX.Bibliography import bibliography
    bibs = []
    for bib in document.getElementsByTagName("bibliography"):
        bib: bibliography
        bibs.append(Path(bib.attributes["files"]).with_suffix(".bib"))
    return bibs
