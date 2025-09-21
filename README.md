# blueprint-gen

*This is a quick demo for a new blueprint tool for Lean. It is currently completely in proof-of-concept stage.*

blueprint-gen is a tool for generating the blueprint directly from Lean.

Nodes in the blueprint consist of theorems and definitions.
Nodes are declared in Lean by the `@[blueprint]` tag.

You may input the nodes defined in Lean using the `\inputleannode{name}` command.

For example, if in the `Example.lean` module of the `Example` library, we have:

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

end MyNat
```

After running `lake build Example:blueprint`, the generated blueprint will be in `.lake/build/blueprint/library/Example.tex`.
You may then write in blueprint LaTeX (typically, `blueprint/src/content.tex`) the following:


```latex
\input{../../.lake/build/blueprint/library/Example}

Input a definition (or theorem) defined in Lean:

\inputleannode{MyNat}

Input the contents (including definitions, theorems, and module docstrings) of an entire module:

\inputleanmodule{Example}
```

After running `leanblueprint pdf` or `leanblueprint web`, you can see the blueprint in the web version or PDF version.
The output of the above example is in [blueprint/src/print.pdf](./blueprint/src/print.pdf).

This tool is built directly on top of [leanblueprint](https://github.com/PatrickMassot/leanblueprint).

- You can declare the informal statement of a theorem or definition with its docstring.
- You can declare the informal proof of a theorem with the `/-- proof -/` tactic.
- The dependencies of a theorem statement and proof are automatically inferred.
  You can override this with the `uses` and `proofUses` options, and with the `using` tactic.
- Whether the statement or proof is ready (i.e. `\leanok`) is inferred from whether it is
  sorry-free.
- For debugging, you can use the `#show_blueprint` and `#show_blueprint_json` commands.
- Use `\inputleannode{name}` to input a node tagged by `@[blueprint]` in Lean.
- Use `\inputleanmodule{Module}` to input the nodes tagged by `@[blueprint]` and module docstrings defined by `/-! ... -/` of an entire module.

See [Example.lean](./Example.lean) for more details.

## Demo

To run the demo [Example.lean](./Example.lean), run:

```sh
lake build Example:blueprint
```

Then the generated blueprint will be in `.lake/build/blueprint/module/Example.tex`.
I have already manually `\input` this file into [blueprint/src/content.tex](./blueprint/src/content.tex), so that you can then run:

```sh
leanblueprint pdf  # to generate the PDF
leanblueprint web  # to generate the web HTML
leanblueprint serve  # to serve the web HTML at localhost
```

(where `leanblueprint` is from [leanblueprint](https://github.com/PatrickMassot/leanblueprint)).
