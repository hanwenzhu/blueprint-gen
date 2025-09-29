# blueprint-gen

*This is a quick demo for a new blueprint tool for Lean. It is currently completely in proof-of-concept stage.*

Blueprint-gen is a tool for generating the blueprint data of a Lean project directly from Lean.

The blueprint is a high-level plan of a Lean project, consisting of a series of nodes (theorems and definitions) and the dependency relations between them.
The purpose of blueprint-gen is to make it easier to write the blueprint by generating blueprint data directly from Lean.

Nodes are declared in Lean by the `@[blueprint]` tag. They are exported to LaTeX, which you may then put in the blueprint.

This tool is built to complement [leanblueprint](https://github.com/PatrickMassot/leanblueprint) and its structure is inspired by [doc-gen4](https://github.com/leanprover/doc-gen4). The idea is inspired by [leanblueprint-extract](https://github.com/AlexKontorovich/PrimeNumberTheoremAnd/tree/main/leanblueprint-extract).

## Example

Consider the following `MyNat` API:

```lean
/-! # Natural numbers -/

@[blueprint "Natural numbers"]
inductive MyNat : Type where
  | zero : MyNat
  | succ : MyNat → MyNat

namespace MyNat

/-!
## Addition
Here we define addition of natural numbers.
-/

/-- Natural number addition. -/
@[blueprint]
def add (a b : MyNat) : MyNat :=
  match b with
  | zero => a
  | succ b => succ (add a b)

/-- For any natural number $a$, $0 + a = a$, where $+$ is Def. `MyNat.add`. -/
@[blueprint, simp]
theorem zero_add (a : MyNat) : add zero a = a := by
  /-- The proof follows by induction. -/
  induction a <;> simp [*, add]

/-- For any natural numbers $a, b$, $(a + 1) + b = (a + b) + 1$. -/
@[blueprint]
theorem succ_add (a b : MyNat) : add (succ a) b = succ (add a b) := by
  /-- Proof by induction on `b`. -/
  -- If the proof contains sorry, the `\leanok` command will not be added
  sorry

/-- For any natural numbers $a, b$, $a + b = b + a$. -/
@[blueprint]
theorem add_comm (a b : MyNat) : add a b = add b a := by
  induction b with
  | zero =>
    -- The inline code `abc` is converted to \ref{abc} if possible.
    /-- The base case follows from `MyNat.zero_add`. -/
    simp [add]
  | succ b ih =>
    /-- The inductive case follows from `MyNat.succ_add`. -/
    sorry_using [succ_add]  -- the `sorry_using` tactic declares that the proof uses succ_add

-- Additional content omitted

end MyNat
```

The output of the above example is:

![Blueprint web](https://raw.githubusercontent.com/hanwenzhu/blueprint-gen-example/refs/heads/main/images/web.png)

With depedency graph:

![Depedency graph](https://raw.githubusercontent.com/hanwenzhu/blueprint-gen-example/refs/heads/main/images/depgraph.png)

## Specifying the blueprint

After tagging with `@[blueprint]`, blueprint-gen will:

1. Extract the statement and proof of a node from docstrings. The Markdown docstrings will be automatically parsed and converted to LaTeX.
2. Infer the dependencies of a node from the constants used in the statement or proof.
3. Infer whether the statement or proof is ready (i.e. `\leanok`) from whether it is sorry-free.
4. Add the node to the generated blueprint.

You may override the constants used in the statement or proof with the `uses` and `proofUses` options, or with the `using` tactic.

To view the generated blueprint data of a node, use `@[blueprint?]`.

## Informal-only nodes

At the start of a project, it is possible that not all theorems have their statements formalized in Lean,
but they nonetheless are in the blueprint.
For "informal-only" theorems or definitions without formal statements, I recommend writing:

```lean
/-- Foo implies bar. -/
@[blueprint] theorem bar_of_foo : (sorry_using [Foo, Bar] : Prop) := by
  /-- Proof is trivial. -/
  sorry_using [of_foo, bar_of]
```

which allows later theorems to reference this theorem.

Alternatively (less recommended), you can use retain informal theorems in the LaTeX blueprint and only write theorems in Lean if they have statement formalized. This will result in "unknown constant" errors in `sorry_using` and `uses` for formal theorems that depend on informal theorems in LaTeX, which you may ignore by `set_option blueprint.ignoreUnknownConstants true`.

## Running blueprint-gen to generate the blueprint

First, install [leanblueprint](https://github.com/PatrickMassot/leanblueprint) and follow the instructions there to set up a blueprint project, if not already done.

To generate the blueprint for a module, first input the generated blueprint to the blueprint document:

```latex
% Typically, in blueprint/src/content.tex

\input{../../.lake/build/blueprint/library/Example}

% Input the blueprint contents of module `Example.MyNat`:
\inputleanmodule{Example.MyNat}

% You may also input only a single node using \inputleannode{MyNat.add}.
```

Then run:

```sh
# Generate the blueprint to .lake/build/blueprint
lake build :blueprint
# Build the blueprint using leanblueprint
leanblueprint pdf
leanblueprint web
```

You may also want to put this in the GitHub Actions workflow typically at `.github/workflows/blueprint.yml`:

```yaml
      # Before "Build blueprint and copy to `home_page/blueprint`":
      - name: Extract blueprint
        run: ~/.elan/bin/lake build :blueprint
```

## Converting from existing blueprint format

With a project that uses the existing leanblueprint format, there is a primitive script that tries to convert to the blueprint-gen format.

Currently, this script depends on a recent version of Python with `loguru` and `pydantic` installed (install by `pip3 install loguru pydantic`).

First go to a clean branch **without any uncomitted changes**, to prevent overwriting any work you have done.

You can then convert to blueprint-gen format by adding `blueprint-gen` as a dependency to lakefile, run `lake update blueprint-gen`, and then run:

```sh
# At the project root
lake build {library name}:blueprintConvert
```

where `{library name}` is the name of the `lean_lib` (in lakefile) that contains the blueprint nodes.

Note that this conversion is not perfect, and for large projects it may end in some small syntax errors. You would need to fix the errors in the converted files. You would also need to manually add the nodes that are not in the project itself (typically, `\mathlibok` nodes) to the blueprint, which will be saved to `extra_nodes.lean`.

Once converted, it is strongly recommended to remove the `uses :=` and `proofUses :=` annoations (and to put them in `sorry_using` if the proof is not yet complete),
in order to let blueprint-gen automatically infer the dependencies.

(For reference, it took me an afternoon to convert [FLT](https://github.com/ImperialCollegeLondon/FLT) to blueprint-gen format and fix all errors.)

## Extracting nodes in JSON

To extract the blueprint nodes in machine-readable format, run:

```sh
lake build :blueprintJson
```

The output will be in `.lake/build/blueprint`.

## TODO

- Currently the LaTeX output (and hence PDF / web outputs) are only in a state of barely working, because it is difficult to translate Markdown to LaTeX. The immediate next improvement will be to explore supporting Verso docstrings (leanprover/lean4#10307), and more specifically, for statement / proof docstrings using `doc.verso`, to generate the LaTeX directly from Verso instead of converting to Markdown and then to LaTeX. One roadblock here is support for citations, which we may have to wait until there is a good solution (e.g. via an extension) that works for both doc-gen4 and our purpose.
