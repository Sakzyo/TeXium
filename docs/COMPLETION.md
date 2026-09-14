# Context-aware code completion

Enable **Settings → Editor → Automatic code completion**. Suggestions appear beside the insertion point as you type. Use **↑ / ↓** to choose, **Tab or Return** to insert, and **Escape** to dismiss. **Control-Space** opens suggestions manually; **Edit → Complete LaTeX** (**Control-Escape**) is also available if macOS reserves Control-Space for input-source switching.

![Project labels with section context](screenshots/context-completion.jpg)

| Context | Suggestions |
| --- | --- |
| `\sec` | Section commands with a title argument, including starred variants |
| `\fra` | `\frac{}{}` with Tab navigation through numerator and denominator |
| `\ref{…}`, `\autoref{…}`, `\cref{…}` | Project label keys, with the preceding section heading and source location |
| `\cite{…}`, `\citep[see][p. 3]{…}`, `\textcite{…}` | Bibliography keys, searchable by key, title, author, year, and other local BibTeX fields |
| `\section{Intro…}` | Matching existing project heading titles |
| `\begin{…}` | Complete environment templates with editable fields |
| `\end{…}` | Environment names only |
| `\input{…}`, `\includegraphics{…}`, `\addbibresource{…}` | Project files filtered for the command |

Completion reads unsaved edits as well as files on disk. In a multi-key citation or reference, it replaces only the current key and preserves the rest. Labels can be found by their section title as well as their key. Command suggestions insert argument braces and place the cursor inside the first argument; Tab moves to subsequent arguments and then beyond the command. Existing arguments remain intact when completing a command in the middle of text. Acceptance is a single undoable edit.

## Complete templates

Type `\begin{fig` and accept **figure** with Tab or Return. TeXium inserts:

```latex
\begin{figure}
    \centering
    \includegraphics[width=0.5\linewidth]{}
    \caption{Caption}
    \label{fig:placeholder}
\end{figure}
```

The cursor starts in the image path, where project-file suggestions remain available. Tab selects `Caption`, then `fig:placeholder`, then moves past `\end{figure}`. Typing replaces a selected default. Shift-Tab returns to the previous field and selects its current contents, even after editing. Escape leaves snippet navigation. Add `\usepackage{graphicx}` to the preamble for figures; templates do not modify the preamble automatically.

| Environment | Inserted structure |
| --- | --- |
| `figure`, `figure*` | Centering, image at half the line width, caption, and label |
| `itemize`, `enumerate` | A matching begin/end pair and first `\item` |
| `description` | First `\item[term]` and its description |
| `table`, `table*` | Editable placement, a two-by-two tabular, caption, and label |
| `tabular`, `array`, `tabularx` | Column specification and two-by-two cells; `tabularx` also includes width |
| Matrix variants, `cases` | Two-by-two editable entries |
| `frame`, `minipage` | Required title or width argument, plus the body |
| Equation/alignment, document, abstract, proof, and other listed environments | Matching begin/end pair with an editable body |

`\includegraphics` also supplies an editable width option and image path. `\documentclass` and `\usepackage` include optional-argument fields. Existing command arguments stay intact when completing a command name.

Templates follow Settings → Editor indentation preferences and the file's line endings. They work with automatic brace closure enabled or disabled, and immediately before or after an opener's closing brace. An opener with existing options, same-line contents, or its own matching end receives only a name completion, preserving the existing structure. New nested lists receive their own closing command. Undo removes an accepted template in one step; native undo may select the restored token, so collapse the selection before requesting completion again.

The conventional figure, list, table, and frame structures were checked against Overleaf's public [environment templates](https://github.com/overleaf/overleaf/blob/main/services/web/frontend/js/features/source-editor/languages/latex/completions/data/environments.ts) and [common command snippets](https://github.com/overleaf/overleaf/blob/main/services/web/frontend/js/features/source-editor/languages/latex/completions/data/top-hundred-snippets.ts). TeXium implements expansion and field navigation in Swift using its own local catalog. Table placement defaults to `htbp`, and the catalog also supplies matrix, minipage, and tabularx structures.

Custom commands declared with `\newcommand`, `\renewcommand`, `\providecommand`, or `\DeclareRobustCommand` in project `.tex`, `.sty`, and `.cls` files are indexed, including their required argument count. Comments, inline `\verb`, and common verbatim/code environments suppress suggestions and symbol indexing. This is a source-aware completion engine, not a TeX interpreter: unusual category-code changes, dynamically constructed macros, and installed package definitions are not expanded.

The interaction follows Overleaf's automatic command/reference workflow and its [project citation search](https://docs.overleaf.com/citing-and-references/adding-citations-and-references/searching-for-references), including filtering by citation key and bibliographic metadata. TeXium uses local project files; reference-manager integrations and Overleaf's online services are not part of this feature.
