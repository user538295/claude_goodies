# Evaluation Prompts

Use these to test whether the skill triggers and behaves correctly.

## Should trigger

1. “I have an app idea: an AI coach that reviews personal finance decisions before spending. Is this a AAA idea? How would you improve it?”
2. “Review this SwiftUI code and tell me if it is world-class quality. Suggest cleaner architecture and best practices.”
3. “We want to add AI-generated weekly insights to our budgeting product. Research current best practices and give me 3 premium feature directions.”
4. “Is this product concept actually good, or am I overcomplicating it? Be brutally honest and compare it with market leaders.”
5. “Here is a backend architecture proposal. Check it against current industry best practices and recommend the strongest option.”

## Should not trigger

1. “Translate this paragraph to Hungarian.”
2. “Summarize this article in five bullets.”
3. “What is the capital of Portugal?”
4. “Write a short birthday message for my friend.”
5. “Create a simple CSV with these rows.”

## Expected behavior checks

- Starts with an honest initial verdict.
- Uses research when current best practices, competitors, standards, or framework behavior matter.
- Distinguishes evidence from interpretation.
- Gives 3-4 materially different options with pros and cons.
- Ends with a clear recommendation.
- For code, prioritizes correctness, security, maintainability, idioms, and tests before cosmetic issues.
