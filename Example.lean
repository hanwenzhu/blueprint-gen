import BlueprintGen


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

/-- For any natural number $a$, $0 + a = a$. -/
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
    -- TODO: how should \refs be resolved?
    -- Either this, or [MyNat.zero_add], or `MyNat.zero_add` with
    -- postprocessing somewhere (in Lean or Pandoc) to convert to \ref.
    have := trivial
    /-- The base case follows from \ref{MyNat.zero_add}. -/
    simp [add]
  | succ b ih =>
    /-- The inductive case follows from \ref{MyNat.succ_add}. -/
    using succ_add  -- the `using` tactic declares that the proof uses succ_add
    sorry

/-! ## Multiplication -/

/-- Natural number multiplication. -/
@[blueprint (uses := [add])]  -- You may override the inferred statement dependencies by `uses`.
def mul (a b : MyNat) : MyNat := sorry

/-- For any natural numbers $a, b$, $a * b = b * a$. -/
@[blueprint]
theorem mul_comm (a b : MyNat) : mul a b = mul b a := by sorry

/-! ## Fermat's Last Theorem -/

/-- Fermat's last theorem. -/
@[blueprint "Taylor--Wiles"
  -- You may override the inferred statement dependencies by `uses`.
  (uses := [mul])
  -- Alternatively to docstring tactics and `using` tactics, proof metadata can be specified
  -- by `proof` and `proofUses`.
  (proof := /-- See \cite{Wiles1995, Taylor-Wiles1995}. -/) (proofUses := [mul_comm])
  (notReady := true) (discussion := 1)]
theorem flt : (sorry : Prop) := sorry

end MyNat

-- Additionally to the above, you can also manually insert nodes from other modules
-- to the blueprint:

-- blueprint_input_node ...
-- blueprint_input_module ...
-- blueprint_input_library ...


-- Finally, these are utility commands for debugging:

#show_blueprint
#show_blueprint_json
