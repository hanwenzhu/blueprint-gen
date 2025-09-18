import subprocess
import re

from pydantic import BaseModel, ConfigDict
from pydantic.alias_generators import to_camel


class BaseSchema(BaseModel):
    model_config = ConfigDict(
        alias_generator=to_camel,
        populate_by_name=True,
    )

# These classes are ported from BlueprintGen/Basic.lean

class NodePart(BaseSchema):
    lean_ok: bool
    text: str
    uses: set[str]
    latex_env: str

class Node(BaseSchema):
    name: str  # Lean identifier (unique)
    statement: NodePart
    proof: NodePart | None
    not_ready: bool
    discussion: int | None
    title: str | None

class Position(BaseSchema):
    line: int
    column: int

class DeclarationRange(BaseSchema):
    pos: Position
    end_pos: Position

class DeclarationLocation(BaseSchema):
    module: str
    range: DeclarationRange

class NodeWithPos(Node):
    has_lean: bool
    location: DeclarationLocation | None
    file: str | None


PANDOC_DEFAULT_WIDTH = 100

def pandoc_convert(from_format: str, to_format: str, input: str) -> str:
    result = subprocess.run(
        [
            "pandoc", "-f", from_format, "-t", to_format,
            f"--columns={PANDOC_DEFAULT_WIDTH}"
        ],
        check=True,
        input=input,
        capture_output=True,
        text=True,
    )
    return result.stdout

def pandoc_convert_latex_to_markdown(latex: str) -> str:
    converted = pandoc_convert(
        "latex",
        # Pandoc's Markdown flavor, disable raw HTML, disable attributes
        "markdown-raw_html-raw_attribute-bracketed_spans-native_divs-native_spans-link_attributes",
        latex
    )
    return converted

def convert_node_latex_to_markdown(node: Node):
    node.statement.text = pandoc_convert_latex_to_markdown(node.statement.text)
    if node.proof is not None:
        node.proof.text = pandoc_convert_latex_to_markdown(node.proof.text)
