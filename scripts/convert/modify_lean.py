"""Utilities for adding @[blueprint] attributes to Lean source files."""

from pathlib import Path
import re

from loguru import logger

from common import Node, NodeWithPos, Position, DeclarationRange, DeclarationLocation, make_docstring


def split_declaration(source: str, pos: Position, end_pos: Position):
    """Split a Lean file into pre, declaration, and post parts."""
    lines = source.splitlines(keepends=True)

    # -1 because Lean Position is 1-indexed
    start = sum(len(lines[i]) for i in range(pos.line - 1)) + pos.column
    end = sum(len(lines[i]) for i in range(end_pos.line - 1)) + end_pos.column

    pre = source[:start]
    decl = source[start:end]
    post = source[end:]

    return pre, decl, post


warned_to_additive = False

def insert_docstring_and_attribute(decl: str, new_docstring: str, new_attr: str) -> str:
    """Inserts attribute and docstring to the declaration.

    Note: This function assumes that the declaration is written in a "parseable" style,
    and corner cases would be fixed manually.
    """

    # open ... in, omit ... in, include ... in, etc (assuming one-line, ending in newline, no interfering comments, etc)
    match = re.search(r"^(?:[a-zA-Z_]+.*?in\n)+", decl)
    if match:
        command_modifiers = match.group(0)
        decl = decl.removeprefix(match.group(0))
    else:
        command_modifiers = ""

    match = re.search(r"^\s*/--(.*?)-/\s*", decl, flags=re.DOTALL)
    if match:
        docstring = f"{new_docstring}\n\n{match.group(1).strip()}"
        decl = decl.removeprefix(match.group(0))
    else:
        docstring = new_docstring

    match = re.search(r"^\s*@\[(.*?)\]\s*", decl, flags=re.DOTALL)
    if match:
        attrs = match.group(1) + ", " + new_attr
        decl = decl.removeprefix(match.group(0))
    else:
        attrs = new_attr

    if decl.startswith("to_additive"):
        global warned_to_additive
        if not warned_to_additive:
            warned_to_additive = True
            logger.warning(
                "Encountered additive declaration(s) generated from @[to_additive]. " +
                "This script currently adds a placeholder, which is likely incorrect. You may decide to:\n" +
                "- Add only the additive declaration in the blueprint by `attribute [blueprint] additive_name`\n" +
                "- Add only the multiplicative declaration in the blueprint by `@[to_additive, blueprint]`\n" +
                "- (Current) add both in the blueprint by `@[to_additive (attr := blueprint)]`"
            )
        decl = decl.removeprefix("to_additive").strip()
        if decl:
            decl = decl + " "
        return f"to_additive (attr := {attrs}) {decl}{make_docstring(docstring)}"

    return f"{command_modifiers}{make_docstring(docstring)}\n@[{attrs}]\n{decl}"


def modify_source(node: Node, file: Path, location: DeclarationLocation):
    """Modify a Lean source file to add @[blueprint] attribute and docstring to the node."""
    source = file.read_text()
    pre, decl, post = split_declaration(source, location.range.pos, location.range.end_pos)
    decl = insert_docstring_and_attribute(decl, new_docstring=node.statement.text, new_attr=node.to_lean_attribute())
    file.write_text(pre + decl + post)


def add_blueprint_gen_import(file: Path):
    """Adds `import BlueprintGen` before the first import in the file."""
    source = file.read_text()
    lines = source.splitlines(keepends=True)
    first_import_index = 0
    for i, line in enumerate(lines):
        if line.startswith("import "):
            first_import_index = i
            break
    lines = lines[:first_import_index] + ["import BlueprintGen\n"] + lines[first_import_index:]
    source = "".join(lines)
    file.write_text(source)


def topological_sort(data: list[tuple[Node, str]]) -> list[tuple[Node, str]]:
    name_to_node: dict[str, tuple[Node, str]] = {node.name: (node, value) for node, value in data}
    
    visited: set[str] = set()
    result: list[tuple[Node, str]] = []

    def visit(name: str):
        if name in visited:
            return
        visited.add(name)

        node, value = name_to_node[name]
        uses = node.statement.uses | (node.proof.uses if node.proof is not None else set())
        for used in uses:
            if used in name_to_node:
                visit(used)
        result.append((node, value))

    for node, _ in data:
        visit(node.name)

    return result


def write_blueprint_attributes(nodes: list[NodeWithPos], modules: list[str], root_file: str):
    # Sort nodes by position, so that we can modify later declarations first
    nodes.sort(
        key=lambda n:
            (n.location.module, n.location.range.pos.line) if n.location is not None else ("", 0),
        reverse=True
    )

    modified_files: set[str] = set()
    upstream_nodes: list[Node] = []

    for node in nodes:
        if not node.has_lean or node.location is None or node.file is None:
            continue

        if not any(node.location.module.split(".")[0] == module for module in modules):
            # These nodes are in the blueprint but not in the project itself
            # Typically, these are \mathlibok nodes
            upstream_nodes.append(node)
            continue

        modify_source(node, Path(node.file), node.location)
        modified_files.add(node.file)

    for file in modified_files:
        add_blueprint_gen_import(Path(file))

    # The extra Lean source to be inserted somewhere in the project,
    # containing (1) upstream (\mathlibok) nodes and (2) informal-only nodes not yet in Lean
    extra_nodes: list[tuple[Node, str]] = []
    for node in upstream_nodes:
        extra_nodes.append((node, f"attribute [{node.to_lean_attribute()}] {node.name}"))
    for node in nodes:
        if not node.has_lean:
            lean = f"{make_docstring(node.statement.text)}\n"
            lean += f"@[{node.to_lean_attribute(add_proof_text=False, add_uses=False)}]\n"
            if node.proof is None:
                lean += f"def {node.name} : (sorry : Type) :=\n  sorry_using [{', '.join(node.statement.uses)}]"
            else:
                lean += f"theorem {node.name} : (sorry_using [{', '.join(node.proof.uses)}] : Prop) := by\n  {make_docstring(node.proof.text, indent=2)}\n  sorry_using [{', '.join(node.statement.uses)}]"
            extra_nodes.append((node, lean))
    
    extra_nodes = topological_sort(extra_nodes)

    if extra_nodes:
        extra_nodes_file = Path(root_file)
        logger.warning(
            f"Outputting some nodes whose locations could not be determined to\n  {extra_nodes_file}\n" +
            "You may want to move them to appropriate locations."
        )
        imports = "import Mathlib\nimport BlueprintGen"
        if extra_nodes_file.exists():
            existing = extra_nodes_file.read_text()
        else:
            existing = ""
        extra_nodes_file.write_text(
            existing + imports + "\n\n" +
            "\n\n".join(lean for _, lean in extra_nodes) + "\n"
        )
