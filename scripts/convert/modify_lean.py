"""Utilities for adding @[blueprint] attributes to Lean source files."""

from pathlib import Path
import re

from loguru import logger

from common import Node, NodeWithPos, Position, DeclarationRange, DeclarationLocation


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

    global warned_to_additive
    if decl.startswith("to_additive") and not warned_to_additive:
        warned_to_additive = True
        logger.warning(
            "Encountered declaration(s) generated from @[to_additive]. " +
            "This script currently will result in Lean syntax error. You may decide to:\n" +
            "- Put the additive declaration in the blueprint by `attribute [blueprint] additive_name`\n" +
            "- Put the multiplicative declaration in the blueprint by `@[to_additive, blueprint]`\n" +
            "- Put both in the blueprint by `@[to_additive (attr := blueprint)]`"
        )

    # open ... in, omit ... in, include ... in, etc (assuming one-line, ending in newline, no interfering comments, etc)
    match = re.search(r"^(?:[a-zA-Z_]+.*?in\n)+", decl)
    if match:
        command_modifiers = match.group(0)
        decl = decl.removeprefix(match.group(0))
    else:
        command_modifiers = ""

    match = re.search(r"^\s*/--(.*?)-/\s*", decl, flags=re.DOTALL)
    if match:
        docstring = f"\n{new_docstring}\n\n{match.group(1).strip()}\n"
        decl = decl.removeprefix(match.group(0))
    else:
        docstring = f"\n{new_docstring}\n"

    match = re.search(r"^\s*@\[(.*?)\]\s*", decl, flags=re.DOTALL)
    if match:
        attrs = match.group(1) + ", " + new_attr
        decl = decl.removeprefix(match.group(0))
    else:
        attrs = new_attr

    return f"{command_modifiers}/--{docstring}-/\n@[{attrs}]\n{decl}"


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
    lines = lines[:first_import_index] + ["import BlueprintGen\n"] + lines[first_import_index:]
    source = "".join(lines)
    file.write_text(source)


def write_blueprint_attributes(nodes: list[NodeWithPos], modules: list[str]):
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
            # logger.warning(
            #     f"Blueprint node in {node.location.module} needs to be manually added:\n" +
            #     f"attribute [{node.to_lean_attribute()}] {node.name}"
            # )
            continue

        modify_source(node, Path(node.file), node.location)
        modified_files.add(node.file)

    for file in modified_files:
        add_blueprint_gen_import(Path(file))

    # The extra Lean source to be inserted somewhere in the project,
    # containing (1) upstream (\mathlibok) nodes and (2) informal-only nodes not yet in Lean
    extra_lean: str = ""
    for node in upstream_nodes:
        extra_lean += f"attribute [{node.to_lean_attribute()}] {node.name}\n\n"
    for node in nodes:
        if not node.has_lean:
            extra_lean += f"/-- {node.statement.text} -/\n"
            extra_lean += f"@[{node.to_lean_attribute}]\n"
            if node.proof is None:
                extra_lean += f"def {node.name} : (sorry : Type) := sorry\n\n"
            else:
                extra_lean += f"theorem {node.name} : (sorry : Prop) := sorry\n\n"

    if extra_lean:
        logger.warning("The Lean code in `extra_nodes.lean` needs to be manually added to your project.")
        Path("extra_nodes.lean").write_text(extra_lean)
