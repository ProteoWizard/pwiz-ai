# Skyline Reporting Layer Architecture

This document describes the **reporting / databinding layer** — the subsystem behind the
Document Grid, the Results grids, report export, and every other place where Skyline shows
tabular data in a customizable grid. It covers classes like `Pivoter`,
`DocumentViewTransformer`, `DataSchema`, `BoundDataGridView`, `BindingListSource`, and the
many supporting types around them.

If you are looking for how the underlying `SrmDocument` works, read
[architecture-data-model.md](architecture-data-model.md) first — the reporting layer sits
*on top of* that immutable document model and exposes it as rows and columns.

## Two Layers: Generic Framework + Skyline Plug-In

The reporting layer is split across two assemblies:

| Layer | Location | Knows about |
|-------|----------|-------------|
| **Generic databinding framework** | `pwiz_tools/Shared/Common/DataBinding/` (`pwiz.Common.DataBinding`) | Nothing Skyline-specific. Reflects over arbitrary .NET objects, builds columns, pivots, filters, sorts, binds to WinForms grids, exports to CSV/TSV. |
| **Skyline plug-in** | `pwiz_tools/Skyline/Model/Databinding/` | How to expose `SrmDocument` as reportable objects (`Protein`, `Peptide`, `Precursor`, `Transition`, `Result`, …) and how to convert legacy reports. |

The generic framework was written to be reusable (it is also used by other tools such as
the ChorusResponse viewer and Topograph). Skyline supplies a handful of subclasses and a set
of **entity objects** that adapt the document model to the framework. Keeping this boundary
in mind is the key to understanding the code: a class in `Shared/Common/DataBinding` must
never reference `SrmDocument`; anything document-aware lives in `Skyline/Model/Databinding`.

## The Big Picture

```
                         ┌─────────────────────────────────────────────┐
   Persisted view        │  ViewSpec  (serializable XML: columns,       │
   (settings / .skyr)     │  filters, sublist, row-source name)         │
                         └───────────────────┬─────────────────────────┘
                                             │ resolve against a DataSchema
                                             ▼
                         ┌─────────────────────────────────────────────┐
   Resolved view         │  ViewInfo  (ColumnDescriptors + DisplayColumns│
                         │  + FilterInfos, all bound to a DataSchema)    │
                         └───────────────────┬─────────────────────────┘
                                             │
   Raw objects   IRowSource ───────────────► │  Pivoter expands one-to-many
   (Proteins,    (GetItems)                  │  collections into RowItems,
    Peptides…)                               │  attaches PivotKeys
                                             ▼
                         ┌─────────────────────────────────────────────┐
   Query result          │  ReportResults  (BigList<RowItem> +          │
                         │  ItemProperties describing the columns)      │
                         └───────────────────┬─────────────────────────┘
                                             │ TransformStack: filter / sort / pivot / cluster
                                             ▼
                         ┌─────────────────────────────────────────────┐
   Bound to UI           │  BindingListView  ◄──  BackgroundQuery       │
                         │        ▲                (off-thread)         │
                         │        │                                     │
                         │  BindingListSource (a WinForms BindingSource)│
                         │        ▲                                     │
                         │  BoundDataGridView   +   NavBar              │
                         └─────────────────────────────────────────────┘
```

The same `ReportResults` that feeds the grid also feeds the CSV/TSV exporter, so what you
see on screen and what you export are produced by identical machinery.

## Part 1 — The Schema and Column Model (generic)

### DataSchema — reflection engine

`DataSchema` (`DataBinding/DataSchema.cs`) is the type-introspection facade. Given a .NET
`Type`, it discovers the properties that can become columns:

- `GetPropertyDescriptors(Type)` calls `TypeDescriptor.GetProperties()` and filters to
  browsable properties, flattening base types and interfaces and unwrapping "chained"
  wrappers such as `Nullable<T>` and `LinkValue<T>`.
- `GetCollectionInfo(Type)` detects `IList<T>` / `IDictionary<K,V>` and returns an
  `ICollectionInfo` so the framework can drill into one-to-many relationships uniformly.
- `IsScalar(Type)` decides whether a type is atomic (primitive, string, enum, `DateTime`) and
  therefore has no further columns to expand.
- `GetColumnCaption(...)` and `IsHidden(...)` apply the metadata attributes (below) to derive
  a localized header and visibility.

A `DataSchema` carries a `DataSchemaLocalizer`, which holds the format provider, the UI
language, and the chain of `ResourceManager`s used to translate invariant column captions
into the user's language. `DataSchemaLocalizer.INVARIANT` is used when exporting
language-neutral output.

`DataSchema` also exposes a `QueryLock` (see threading, below) used to serialize queries
against caches that change when the underlying data changes.

### Attributes drive column metadata

Columns are configured declaratively by attributes on the entity properties. The framework
reads these during `GetPropertyDescriptors`:

| Attribute | Effect |
|-----------|--------|
| `[InvariantDisplayName("…")]` | The **language-neutral** column name; also the stable identifier used in resource lookups. |
| `[ColumnCaption(...)]` | Supplies an `IColumnCaption` for richer/localized captions. |
| `[Format("0.####", NullValue="#N/A")]` | Number/date format string and how nulls render. |
| `[Hidden]` / `[HideWhen(...)]` | Hide a column outright, or hide it when an ancestor is of a given type. |
| `[ChildDisplayName("Peptide{0}")]` | Prefix/format applied to a child object's columns (e.g. `ProteomicSequence`'s sub-columns). |
| `[OneToMany(...)]` | Marks a collection property; names the index/item columns and the back-reference foreign key to hide. |
| `[Expensive]` | Marks a value as costly to compute (the grid avoids auto-sizing on it). |
| `[InUiModes(...)]` / `ExceptInUiMode` | Show the column only in certain UI modes (proteomic vs. small-molecule vs. mixed). |
| `[RowSource("…")]` | On a type, names the row source it represents. |

### PropertyPath — the column identity

A `PropertyPath` (`DataBinding/PropertyPath.cs`) is an immutable, serializable path through
the object graph. It is the canonical, language-independent **identity** of a column:

- `.Property("Name")` — a property access, serialized as `.Name`.
- `!Key` — a dictionary/collection lookup of a specific key.
- `!*` (`LookupAllItems()`) — an *unbound* lookup over every element of a collection; this is
  what makes a property "pivoted" or "expandable".

Example: `Proteins!*.Peptides!*.Results!*.Value.RetentionTime` walks from the document root
through every protein, every peptide, every replicate result, to the retention time. The
string form round-trips via `PropertyPath.Parse()` and is exactly what is stored in a saved
view's `<column name="…">`.

### ColumnDescriptor — a column bound to the schema

Where `PropertyPath` is just an identity, a `ColumnDescriptor`
(`DataBinding/ColumnDescriptor.cs`) is that path **resolved against a `DataSchema`** — it
knows the actual `Type` at that point in the graph and how to fetch the value. It is
polymorphic:

- **Root** — represents the row object itself; `GetPropertyValue` returns `rowItem.Value`.
- **Reflected** — wraps a `System.ComponentModel.PropertyDescriptor`; fetches the parent's
  value then reads the property.
- **Collection** — wraps an `ICollectionInfo`; its `PropertyPath` ends in `!*`, and it pulls a
  specific element out using a key taken from the `RowItem`'s `RowKey`/`PivotKey`.
- **Grouped** — used for aggregated/pivoted value columns; reads from an indexed list of
  grouped values.

`ColumnDescriptor` provides the navigation methods the rest of the framework relies on:
`ResolveChild(name)`, `GetCollectionColumn()`, `GetChildColumns()`, `CollectionAncestor()`,
and the value accessors `GetPropertyValue(rowItem, pivotKey)` / `SetValue(...)`.

### ViewSpec → ViewInfo → DisplayColumn

There are three representations of "a view", and the distinction matters:

| Type | Mutability | Role |
|------|-----------|------|
| `ViewSpec` / `ColumnSpec` | Serializable value object | What's stored on disk: column `PropertyPath` strings, caption/format overrides, filters, the `SublistId`, the row-source name. No live types. |
| `ViewInfo` | Resolved, in-memory | A `ViewSpec` whose every `PropertyPath` has been resolved to a `ColumnDescriptor` against a `DataSchema`. |
| `DisplayColumn` | Per-column, in-memory | One per visible column in a `ViewInfo`: pairs a `ColumnSpec` (user overrides) with its resolved `ColumnDescriptor`, and exposes `GetValue`, `GetColumnCaption`, `GetAttributes` for the grid. |

`ViewInfo`'s constructor (`DataBinding/ViewInfo.cs`) does the resolution: for each
`ColumnSpec` it calls `GetColumnDescriptor(propertyPath)`, which walks the path one segment at
a time (caching as it goes) using `ColumnDescriptor.ResolveChild` / `GetCollectionColumn`, and
wraps the result in a `DisplayColumn`. Filters resolve the same way into `FilterInfo`s.
`ViewInfo.GetViewSpec()` performs the reverse, reconstructing a serializable spec from the
resolved state.

At the very end of the pipeline, each column the grid actually binds to is a
`ColumnPropertyDescriptor` — a `System.ComponentModel.PropertyDescriptor` whose component
type is `RowItem` and which delegates `GetValue`/`SetValue` to its `DisplayColumn`. This is
the adapter that lets a standard WinForms `DataGridView` read our object graph.

## Part 2 — The Query Pipeline (generic)

This is the heart of the layer: turning a `ViewInfo` plus a row source into the
`ReportResults` that the grid shows.

### IRowSource and RowItem

- `IRowSource` (`DataBinding/IRowSource.cs`) is the abstraction over the raw input: it has
  `GetItems()` and a `RowSourceChanged` event. Skyline's implementations return live
  collections of entity objects (proteins, peptides, …).
- A `RowItem` (`DataBinding/RowItem.cs`) is a lightweight, **immutable** wrapper around one
  source object (`Value`). As it passes through the pipeline it accumulates two kinds of key:
  - **`RowKey`** — its position within nested *sublist* collections (which rows it expanded
    from). Built up during `Expand`.
  - **`PivotKeys`** — identifiers for the *pivoted* (horizontal) dimensions it participates
    in. Added during `Pivot`.

  `RowItem` uses subclasses (`WithRowKey`, `WithPivotKeys`) so that the common case (no keys)
  costs nothing; `SetRowKey`/`SetPivotKeys` return new instances rather than mutating.

### Pivoter — expand and pivot

`Pivoter` (`DataBinding/Internal/Pivoter.cs`) is the class that turns a flat list of source
objects into the final rows-and-columns shape. Its constructor partitions the view's
collection columns into two sets based on the view's `SublistId`:

- **SublistColumns** — collections whose path is a prefix of the `SublistId`. These expand
  **vertically**: each element becomes a *separate row*.
- **PivotColumns** — every other collection. These expand **horizontally**: each element
  becomes a *separate column* (e.g. one column per replicate). This is how Skyline produces a
  "pivoted" report with a block of columns repeated per replicate.

The work happens in three steps:

1. **`Expand`** — recurses through the `SublistColumns`, and for each element of each
   collection produces a child `RowItem` with the element's key appended to its `RowKey`.
   This is what turns one protein into many peptide rows, etc.
2. **`Pivot`** — for each `PivotColumn`, attaches `PivotKey`s to the row identifying which
   horizontal slice each value belongs to.
3. **`Filter`** — applies the `ViewInfo`'s built-in filters, dropping rows.

`ExpandAndPivot()` runs Expand → Pivot → Filter over all input rows (parallelized with
`ParallelEx.For`, results merged into a `BigList<RowItem>`), and `GetItemProperties()`
computes the final column set — one `ColumnPropertyDescriptor` per non-pivoted column, and
one per `PivotKey` value for pivoted columns. When the view `HasTotals`, `GroupAndTotal()`
groups rows and produces aggregate/value columns instead.

> The class header in `Pivoter.cs` is the canonical short description of this three-step
> Expand → aggregate → pivot transformation — worth reading directly.

### ReportResults

`ReportResults` (`DataBinding/ReportResults.cs`) is the output container: a
`BigList<RowItem>` of the rows plus an `ItemProperties` describing the columns. (`BigList` is
used so that very large reports don't blow up on a single contiguous array.) This is the
single object consumed by both the grid and the exporter.

### TransformStack — interactive filter/sort/pivot/cluster

On top of the view's own filters, the user can interactively layer additional
transformations from the NavBar: quick filters, sorts, pivots, and clustering. These are
modeled as an ordered, immutable `TransformStack` (`DataBinding/Layout/TransformStack.cs`) of
`IRowTransform`s (`RowFilter`, `PivotSpec`). The stack has a `StackIndex` cursor so the user
can step back through pivot layers ("drill up"). `AbstractQuery.Transform()` walks the stack,
applying each `RowFilter` (filter then sort) or `PivotSpec` (group and total) in turn.

### Interactive pivot/aggregate: PivotSpec and GroupAndTotaler

After a report definition has produced its rows and columns, the user can interactively
**pivot and aggregate** the grid — choose which columns become row headers, which become
column headers, and which become aggregated values (Sum, Mean, CV, …). This is the
"Group/Total" or "Pivot Editor" feature on the NavBar, and it is **a transform applied on top
of the finished report**, not part of the report definition. It is the most important thing to
understand here: by the time a `PivotSpec` runs, the `ViewInfo`/`Pivoter` work is already done;
the pivot operates purely on the rows-and-columns the report produced.

#### PivotSpec — what the user chose

`PivotSpec` (`DataBinding/Layout/PivotSpec.cs`) is an immutable, serializable `IRowTransform`
describing one pivot/aggregate level. It has three lists:

- **`RowHeaders`** (`Column[]`) — columns whose distinct value combinations define the output
  rows (the "group by" keys).
- **`ColumnHeaders`** (`Column[]`) — columns whose distinct value combinations fan the value
  columns out horizontally (one block of value columns per distinct column-header value).
- **`Values`** (`AggregateColumn[]`) — columns to aggregate, each paired with an
  `AggregateOperation`.

A subtle but crucial detail: a `PivotSpec.Column` does **not** reference a column by
`PropertyPath`. It references it by **`ColumnId`**, which is the column's *invariant display
caption* (`ColumnId.GetColumnId` = `dataPropertyDescriptor.ColumnCaption.GetCaption(
DataSchemaLocalizer.INVARIANT)`). The pivot layer matches up columns by their (language-neutral)
header text, because at this stage it is working against the already-produced
`ItemProperties`, not against the object graph. This is why a `PivotSpec` survives across
reports that expose a column with the same caption, and why it is keyed differently from
everything in Parts 1–2.

#### AggregateOperation

`AggregateOperation` (`DataBinding/AggregateOperation.cs`) is the set of aggregations, each a
singleton: `Sum`, `Count`, `CountDistinct`, `Mean`, `Median`, `Min`, `Max`, `StdDev`, `Cv`.
Each knows `IsValidForType`, the result `GetPropertyType` (e.g. `Count` → `int`, numeric
aggregates → `double`, `Min`/`Max` → the original type), `CalculateValue(dataSchema, values)`,
and how to qualify the column caption (e.g. *"CV of Area"* via `AggregateCaption`). Numeric
aggregates unwrap and `Convert.ToDouble` each value, silently skipping ones that don't convert.

#### GroupAndTotaler — the engine

When `AbstractQuery.Transform` hits a `PivotSpec` in the stack, it calls
`GroupAndTotaler.GroupAndTotal(...)` (`DataBinding/Internal/GroupAndTotaler.cs`), which rewrites
the `ReportResults` entirely:

1. Resolve each `PivotSpec.Column`'s `ColumnId` back to the actual `DataPropertyDescriptor`(s)
   in the input's `ItemProperties` (lookup keyed by invariant caption).
2. Group the input rows by the tuple of **row-header** values.
3. Within each group, bucket rows by the tuple of **column-header** values, assigning each
   distinct combination an index. For every (column-header bucket × value column) pair it emits
   one output property descriptor and accumulates the non-null values.
4. For each cell, call the column's `AggregateOperation.CalculateValue`.
5. Emit one output `RowItem` per row-header group.

The output is a **fundamentally different row shape**. Each output `RowItem`'s `Value` is a
positional `List<object>` (row-header values followed by aggregated cells), and the columns are
`IndexedPropertyDescriptor` / `WrappedDataPropertyDescriptor` that read by index — *not*
`ColumnPropertyDescriptor`s reading from an entity. Value-column captions are qualified with
their column-header values via `CaptionComponentList`, and carry a `PivotedColumnId` so the
grid still knows they belong to a pivoted block. (Row headers that are sub-properties of other
row headers are stitched into a parent/child hierarchy by `GetRowHeaderPropertyDescriptors`, so
e.g. a peptide and its protein nest correctly.)

#### How it gets applied

The NavBar's Group/Total split-button calls `NavBar.ShowPivotDialog` →
`PivotEditor.ShowPivotEditor`, which builds a `PivotSpec` and pushes it onto the live
`TransformStack`:

```csharp
bindingListSource.BindingListView.TransformStack =
    bindingListSource.BindingListView.TransformStack.PushTransform(pivotSpec);
```

Because it's just another `IRowTransform`, a pivot can sit on top of an interactive filter, and
the user can stack multiple pivot levels and `StackIndex` back down through them. Pivots are
saved as part of a `ViewLayout` (with the column formats and clustering), not as part of the
`ViewSpec` — consistent with being a post-report presentation choice.

#### Don't confuse this with report-definition totals

There is a *second*, older grouping mechanism that lives **inside** the report definition: a
`ColumnSpec` can carry a `TotalOperation` (`GroupBy`, `PivotKey`, `PivotValue`). When a view
`HasTotals`, the grouping happens during the Pivot phase in `Pivoter.GroupAndTotal` (Part 2),
as the report is built. The interactive `PivotSpec`/`GroupAndTotaler` path described here is the
newer, layout-level equivalent applied *after* the report. They produce similar-looking pivoted
output but are different code paths reached from different places (the customize-report dialog's
column "Total" setting vs. the grid's Pivot Editor).

### Threading: BackgroundQuery vs ForegroundQuery

Reports can be expensive, so by default they run **off the UI thread**:

- `QueryRequestor` owns the lifecycle. On `Requery()` it wraps the `IRowSource` in a
  `RowSourceWrapper` (which converts raw objects to `RowItem`s and caches them) and starts a
  query.
- If the `BindingListView` was given an `EventTaskScheduler`, the query runs as a
  `BackgroundQuery` on a thread-pool thread; otherwise a `ForegroundQuery` runs it inline
  (used in tests and CLI). Both share the same logic in `AbstractQuery.RunAll()`:
  `Pivot()` → `Transform()` → optional clustering.
- A `BackgroundQuery` takes a **read lock** on the `DataSchema.QueryLock` while it runs, and
  is cancellable: if the data changes (the row source raises `RowSourceChanged`) the in-flight
  query is cancelled and restarted. When it finishes it marshals the `ReportResults` back to
  the UI thread via the `EventTaskScheduler`, where `BindingListView.UpdateResults()` swaps in
  the new rows and raises `ListChanged`.

This is why grids stay responsive during large reports, and why a report can show a
"transforming…" indicator while the background query is in flight.

## Part 3 — The UI Controls (generic)

### BindingListView and BindingListSource

- `BindingListView` (`DataBinding/Internal/BindingListView.cs`) is the `IBindingList`
  implementation that the grid actually binds to. It owns the current `ViewInfo`, `RowSource`,
  `TransformStack`, and the latest `ReportResults`, and drives requeries when any of them
  change.
- `BindingListSource` (`DataBinding/Controls/BindingListSource.cs`) **extends the WinForms
  `BindingSource`** and wraps a `BindingListView` as its `DataSource`. It is the public
  surface the rest of the app talks to: it exposes `ViewInfo`, `RowSource`, `RowFilter`,
  `ColumnFormats`, `ClusteringSpec`, and the `SetViewContext(...)` / `ApplyLayout(...)`
  methods. Code that wants to show a grid sets up a `BindingListSource`, not a
  `BindingListView` directly.

### BoundDataGridView

`BoundDataGridView` (`DataBinding/Controls/BoundDataGridView.cs`) is a `DataGridView`
subclass that auto-wires itself to a `BindingListSource`. On `OnDataBindingComplete` it reads
the `ItemProperties` and rebuilds its columns by asking the `IViewContext` to create each
`DataGridViewColumn` (`UpdateColumns` → `viewContext.CreateGridViewColumn`). It also applies
saved column widths/formats (`ColumnFormats`), renders cell background colors from an optional
`ReportColorScheme` (clustering heat-maps), routes hyperlink clicks to `ILinkValue` cells, and
funnels cell edits through `BindingListSource.ValidateRow()`.

### NavBar

`NavBar` (`DataBinding/Controls/NavBar.cs`) is the toolbar above the grid. It drives:
- **View selection** — populates its dropdown from `IViewContext.GetViewSpecList(...)`,
  grouping built-in vs. custom views; `ApplyView` loads the chosen view via
  `IViewContext.GetViewInfo` and pushes it into the `BindingListSource`.
- **Customize view** — opens the `ViewEditor`.
- **Filtering** — the text box sets `BindingListSource.RowFilter`.
- **Pivot / group / layout** — opens the `PivotEditor`, pushes `PivotSpec`s onto the
  `TransformStack`, and saves/restores `ViewLayout`s (column formats + transforms +
  clustering) via the view context.
- **Find / export / row navigation** — standard grid affordances.

### IViewContext / AbstractViewContext — the application bridge

`IViewContext` (`DataBinding/IViewContext.cs`) is the seam between the generic framework and
the host application. It answers questions only the app can answer: what views exist
(`GetViewSpecList`), what the row source for a view is (`GetRowSource`), how to persist views
and layouts, how to create grid columns, how to handle delete/edit/data errors, and how to
export. `AbstractViewContext` provides the shared implementation (view persistence, the
export pipeline, default column creation); Skyline subclasses it (see Part 4).

### Export to CSV/TSV

Export reuses the exact same `ReportResults`. `AbstractViewContext.Export` shows the save
dialog, picks a separator from the chosen file type, and hands off to a `DsvReportExporter`
that writes a header row and then each `RowItem` through a `DsvWriter`. `DsvWriter` formats
each cell (applying the column's format string and culture) and escapes fields for CSV/TSV.
Because the exporter walks a `RowItemEnumerator`, large reports stream to disk rather than
materializing entirely.

## Part 4 — Plugging Skyline In (Skyline-specific)

Everything above is document-agnostic. Skyline's `Model/Databinding` folder supplies the
adapter.

### SkylineDataSchema

`SkylineDataSchema` (`Model/Databinding/SkylineDataSchema.cs`) extends `DataSchema` and adds
the document context:

- Holds an `IDocumentContainer`, listens for document changes, and invalidates its caches
  (replicates, result files, annotation/normalization calculators) under the `QueryLock` when
  the document changes.
- Overrides `GetPropertyDescriptors(Type)` to **append dynamic columns** that aren't ordinary
  reflected properties: user-defined annotations (`AnnotationPropertyDescriptor`), isotope
  ratios and RDOTP (`RatioPropertyDescriptor`), and list-defined columns. These exist only if
  the document defines them, so they can't be static properties.
- Provides `ModifyDocument` / `BeginBatchModifyDocument` / `CommitBatchModifyDocument` so that
  editing a grid cell (or pasting a block) turns into a proper, audit-logged document change —
  a batch of cell edits collapses into a single undo entry.

### Entities: wrapping DocNodes as rows

The reportable objects live in `Model/Databinding/Entities/`. The hierarchy mirrors the
document tree:

```
SkylineObject                      (base: knows its DataSchema, supports annotations)
└── SkylineDocNode<TDocNode>       (wraps a DocNode by IdentityPath; cached, document-aware)
    ├── Protein     (PeptideGroupDocNode)
    ├── Peptide     (PeptideDocNode)
    ├── Precursor   (TransitionGroupDocNode)
    └── Transition  (TransitionDocNode)
```

Key points:

- An entity does **not** hold its `DocNode` directly. It holds an `IdentityPath` and a
  `CachedValue<TDocNode>` that re-fetches from the current document, invalidating whenever
  `SrmDocument.ReferenceId` changes. This is what keeps the grid live as the document is
  edited (it dovetails with the immutable-document model in
  [architecture-data-model.md](architecture-data-model.md)).
- Properties become columns. The attribute pattern from Part 1 is used heavily, e.g.:

  ```csharp
  [ProteomicDisplayName("ProteinName")]            // caption in proteomic mode
  [InvariantDisplayName("MoleculeListName")]       // stable identifier / small-molecule caption
  public string Name { get; set; }                 // settable → editable grid cell
  ```

  A settable property whose setter calls `ChangeDocNode` / `ModifyDocument` becomes an
  **editable** grid cell.
- Child collections (`Protein.Peptides`, `Peptide.Precursors`, …) are exposed as `IList<…>`
  of entities, materialized lazily through `CachedValues`. The Pivoter's `Expand` walks these
  to produce child rows.

### Per-replicate results

Replicate-specific measurements are exposed as a dictionary on each entity:

```csharp
public IDictionary<ResultKey, PeptideResult> Results { get; }   // keyed by replicate+file
```

`SkylineDocNode.MakeChromInfoResultsMap<TChromInfo,TResult>()` builds these by walking the
node's `Results<TChromInfo>` arrays (the positional per-replicate arrays described in the
data-model doc) and creating a `Result` object per replicate/file, keyed by
`ResultKey(replicateIndex, fileIndex)`. The `Result` subclasses (`PeptideResult`,
`PrecursorResult`, `TransitionResult`) expose peak area, retention time, mass error, ratios,
etc., and link back to both the parent entity and the `ResultFile`. Because `Results` is an
`IDictionary` with an `!*` unbound lookup, it is a natural **pivot column** — that's how a
report ends up with one "Retention Time" column per replicate.

### Row sources and factories

- `SkylineRowSource` / `RowFactories` (`Model/Databinding/RowFactories.cs`) register the named
  row sources ("Proteins", "Peptides", "Precursors", "Transitions", replicate/result lists,
  fold-change, candidate peak groups, …) and know how to materialize each one from the
  current document.
- `Collections/SkylineObjectList<T>` and `NodeList<T>` are the `IRowSource` implementations
  that produce these entity collections and raise `ListChanged` when the document changes, so
  the grid requeries automatically. `Proteins`, `Peptides`, etc. are the concrete lists,
  parameterized by their tree depth.

### DocumentViewTransformer

`DocumentViewTransformer` (`Model/Databinding/DocumentViewTransformer.cs`) implements
`IViewTransformer`. The Document Grid's customize-view dialog presents a *single* logical root
(`SkylineDocument`) so users don't have to pick "Peptides vs Precursors vs Transitions" up
front. This class translates between that document-rooted form and the most efficient concrete
row type:

- `MakeIntoDocumentView` rewrites a view that selects from `Peptides`/`Precursors`/etc. so its
  columns are rooted at `SkylineDocument` (e.g. `Protein.Name` → `Proteins!*.Name`).
- `ConvertFromDocumentView` does the inverse, picking the deepest entity actually referenced as
  the row type so the Pivoter does the least work.

It works purely by remapping `PropertyPath`s on the `ViewSpec`'s columns, filters, and
`SublistId`, using the per-row-type mapping tables (`MappingFromProteins`,
`MappingFromPeptides`, `MappingFromPrecursors`, `MappingFromTransitions`,
`MappingFromReplicates`).

#### The same column has two different PropertyPaths

This is the single most confusing thing about the reporting layer, and it trips up almost
everyone who writes a functional test against the Document Grid. **A column's `PropertyPath`
in the customize-view editor is not the same as its `PropertyPath` on the live grid.**

The transformer is installed on the editor only — `DocumentGridViewContext.CreateViewEditor`
calls `viewEditor.SetViewTransformer(new DocumentViewTransformer())`. So:

- **Inside the ViewEditor** (the "Customize Report"/"Edit Report" dialog), the
  `ViewEditorWidget` calls `TransformView` to display the column tree, and every
  `PropertyPath` is rooted at **`SkylineDocument`**: `Proteins!*`, `Proteins!*.Peptides!*`,
  `Replicates!*`, and so on. There is one unified tree no matter which row source you picked.
- **On the live grid** (`DocumentGridForm` / `BoundDataGridView` / the `BindingListSource`),
  the view has been run through `ConvertFromDocumentView`, so its `ParentColumn.PropertyType`
  is one of the **`Entities` classes** — `Protein`, `Peptide`, `Precursor`, `Transition`, or
  `Replicate` — chosen as the *deepest* entity any column touches. Every grid column's
  `PropertyPath` is rooted at **that entity**, not at `SkylineDocument`.

The transformation isn't just chopping off a prefix. Because the grid is rooted at a single
entity, ancestors and sibling result levels are reached by **navigating up** rather than by
descending through collections. Concretely, for a report whose row source is **Transitions**:

| Logical column | In the ViewEditor (rooted at `SkylineDocument`) | On the grid (rooted at `Transition`) |
|----------------|--------------------------------------------------|--------------------------------------|
| The transition itself | `Proteins!*.Peptides!*.Precursors!*.Transitions!*` | `~` (i.e. `PropertyPath.Root`) |
| Peptide sequence | `Proteins!*.Peptides!*.Sequence` | `Precursor.Peptide.Sequence` |
| Protein name | `Proteins!*.Name` | `Precursor.Peptide.Protein.Name` |
| Replicate of a result | `Replicates!*` | `Results!*.Value.PrecursorResult.PeptideResult.ResultFile.Replicate` |
| Transition peak area | `Proteins!*.…!*.Transitions!*.Results!*.Value.Area` | `Results!*.Value.Area` |

Notice the replicate column: in the editor it is a top-level `Replicates!*` collection, but on
a transition-rooted grid the only way to reach a replicate is *up* from a per-result object
(`TransitionResult` → `PrecursorResult` → `PeptideResult` → `ResultFile` → `Replicate`). The
mapping tables in `DocumentViewTransformer` encode exactly these equivalences.

`ColumnResolver` (next section) and the `ReplicatePivotColumns` / `SublistPaths` helpers reuse
the same mapping (`GetMappingForRowType`, `GetReplicatePropertyPath`,
`GetResultFilePropertyPath`) so that everything agrees on which entity root a set of columns
implies.

#### Gotcha for functional tests

A test that customizes a report and then reads cells from the grid **must switch
`PropertyPath` vocabularies halfway through**: `SkylineDocument`-rooted paths while driving the
editor, entity-rooted paths while inspecting the grid. Using the editor path to look up a grid
column (or vice versa) silently fails — `FindColumn` returns `null` and the test blames the
wrong thing.

`DocumentGridChromatogramDataTest` is the canonical example. While building the view it adds
columns with document-rooted paths:

```csharp
// In the ViewEditor: paths start at SkylineDocument
var propertyPathTransitions = PropertyPath.Root
    .Property(nameof(SkylineDocument.Proteins)).LookupAllItems()
    .Property(nameof(Protein.Peptides)).LookupAllItems()
    .Property(nameof(Peptide.Precursors)).LookupAllItems()
    .Property(nameof(Precursor.Transitions)).LookupAllItems();
viewEditor.ChooseColumnsTab.AddColumn(propertyPathTransitions);
viewEditor.ChooseColumnsTab.AddColumn(
    PropertyPath.Root.Property(nameof(SkylineDocument.Replicates)).LookupAllItems());
```

…but when it later verifies the grid, it finds those same columns with **Transition-rooted**
paths:

```csharp
// On the grid: paths start at the Transition entity
var colTransition = documentGridForm.FindColumn(PropertyPath.Root);   // the row itself
var colReplicate = documentGridForm.FindColumn(PropertyPath.Root
    .Property(nameof(Transition.Results)).LookupAllItems()
    .Property(nameof(KeyValuePair<object, object>.Value))
    .Property(nameof(TransitionResult.PrecursorResult))
    .Property(nameof(PrecursorResult.PeptideResult))
    .Property(nameof(PeptideResult.ResultFile))
    .Property(nameof(ResultFile.Replicate)));
```

Rules of thumb when writing such tests:

- Driving `viewEditor.ChooseColumnsTab` (`TrySelect`, `AddColumn`, `RemoveColumns`)? Use
  **`SkylineDocument`-rooted** paths (start at `Proteins`/`Peptides`/`Precursors`/
  `Transitions`/`Replicates`).
- Calling `documentGridForm.FindColumn(...)`, reading `dataGridView.Rows[i].Cells[...]`, or
  inspecting a `ColumnPropertyDescriptor`? Use **entity-rooted** paths for the grid's row type
  (`PropertyPath.Root` *is* that entity; ancestors are reached by navigating up).
- Not sure what row type the grid resolved to? It's
  `bindingListSource.ViewInfo.ParentColumn.PropertyType`, and it's the deepest entity any
  column touches — adding a single transition column to an otherwise peptide-level report
  pushes the whole grid to a `Transition` root.
- The live **Results grid** (`LiveResultsGrid`) and other non-document grids do **not** install
  this transformer, so their editor and grid paths already agree — this split is specific to
  the Document Grid.

### ColumnResolver

`ColumnResolver` (`Model/Databinding/ColumnResolver.cs`) maps human/invariant column names to
`PropertyPath`s and chooses the **minimal-depth row source** that can supply all requested
columns (fewest collection traversals). This keeps reports efficient and underlies report
documentation/topic grouping.

### Legacy report conversion

Skyline predates this databinding layer; old reports were Hibernate-style `ReportSpec`
queries. Two classes bridge the formats:

- `ReportOrViewSpec` (`Model/Databinding/ReportOrViewSpec.cs`) is a union that, on read,
  sniffs the XML to decide whether it's an old `ReportSpec` or a new `ViewSpecLayout`.
- `ReportSpecConverter` (`Model/Databinding/ReportSpecConverter.cs`) converts an old
  `ReportSpec` into a `ViewSpec`: it picks the new root table type, converts each
  `ReportColumn` (handling annotations, ratios, and navigations specially) into a `ColumnSpec`
  with the right `PropertyPath`, and adds the implicit "is not blank" result filters the old
  reports applied. This is how legacy `.skyr` files and built-in default reports keep working.

## Naming Cheat-Sheet

| Class | One-line role |
|-------|---------------|
| `DataSchema` | Reflects over types to discover columns; localization + query lock. |
| `SkylineDataSchema` | `DataSchema` + live `SrmDocument` context, dynamic annotation/ratio columns, cell-edit → document modification. |
| `PropertyPath` | Serializable identity of a column (path through the object graph). |
| `ColumnDescriptor` | A `PropertyPath` resolved against a `DataSchema`; fetches values. |
| `ColumnSpec` / `ViewSpec` | Serializable column / view definition (what's on disk). |
| `ViewInfo` | A `ViewSpec` resolved into `ColumnDescriptor`s + `DisplayColumn`s. |
| `DisplayColumn` | One resolved column (spec + descriptor) with UI accessors. |
| `ColumnPropertyDescriptor` | `PropertyDescriptor` over a `RowItem` that the grid binds to. |
| `IRowSource` | Supplies the raw objects to report on; raises change events. |
| `RowItem` | Immutable wrapper of one source object + its `RowKey`/`PivotKeys`. |
| `Pivoter` | Expands one-to-many collections into rows, pivots others into columns. |
| `ReportResults` | The query output: `BigList<RowItem>` + column `ItemProperties`. |
| `TransformStack` | Ordered, undoable interactive filters/sorts/pivots/clustering. |
| `PivotSpec` | Interactive pivot/aggregate spec: row headers, column headers, value columns (by `ColumnId` = invariant caption). An `IRowTransform`. |
| `GroupAndTotaler` | Applies a `PivotSpec`: groups rows, fans out columns, aggregates; emits positional-`List<object>` rows. |
| `AggregateOperation` | Sum/Count/CountDistinct/Mean/Median/Min/Max/StdDev/Cv. |
| `ColumnId` | A column's invariant display caption; how `PivotSpec` references columns. |
| `TotalOperation` | The *report-definition* grouping flag on a `ColumnSpec` (`GroupBy`/`PivotKey`/`PivotValue`) — distinct from the interactive `PivotSpec`. |
| `BackgroundQuery` / `ForegroundQuery` | Run the pipeline off / on the calling thread. |
| `BindingListView` | The `IBindingList` the grid binds to; owns view + results. |
| `BindingListSource` | WinForms `BindingSource` wrapper over `BindingListView`. |
| `BoundDataGridView` | `DataGridView` that auto-builds columns from `ItemProperties`. |
| `NavBar` | Toolbar: view selection, filter, pivot, layout, export. |
| `IViewContext` / `AbstractViewContext` | App bridge: views, row sources, persistence, columns, export. |
| `DocumentViewTransformer` | Maps Skyline views to/from the unified `SkylineDocument` root. |
| `RowFactories` / `NodeList` | Build/refresh the entity collections used as row sources. |
| `Protein`/`Peptide`/`Precursor`/`Transition` | Entities wrapping DocNodes as reportable rows. |
| `Result` (+ subclasses) | Per-replicate/per-file measurement rows, keyed by `ResultKey`. |
| `ReportSpecConverter` / `ReportOrViewSpec` | Convert legacy `ReportSpec` reports to `ViewSpec`. |

## See Also

Generic framework (`pwiz_tools/Shared/Common/DataBinding/`):
- `DataSchema.cs`, `DataSchemaLocalizer.cs` — schema + localization
- `PropertyPath.cs`, `ColumnDescriptor.cs`, `ColumnSpec.cs`, `ViewInfo.cs`, `DisplayColumn.cs`
- `CollectionInfo.cs` — `IList`/`IDictionary` abstraction
- `RowItem.cs`, `ReportResults.cs`, `IRowSource.cs`
- `Internal/Pivoter.cs` — read the class header for the Expand/aggregate/pivot summary
- `Internal/BindingListView.cs`, `Internal/BackgroundQuery.cs`, `Internal/ForegroundQuery.cs`,
  `Internal/QueryRequestor.cs`, `Internal/QueryResults.cs`, `Internal/AbstractQuery.cs`
- `Layout/TransformStack.cs`, `Layout/ViewLayout.cs`, `Layout/PivotSpec.cs`, `Layout/ColumnId.cs`
- `Internal/GroupAndTotaler.cs`, `AggregateOperation.cs`, `TotalOperation.cs` — interactive
  pivot/aggregate (and the report-definition `TotalOperation` it contrasts with)
- `Controls/BindingListSource.cs`, `Controls/BoundDataGridView.cs`, `Controls/NavBar.cs`,
  `Controls/PivotEditor.cs`
- `IViewContext.cs`, `AbstractViewContext.cs`, `IViewTransformer.cs`
- `ReportExporter.cs`, `DsvWriter.cs` — export path

Skyline plug-in (`pwiz_tools/Skyline/Model/Databinding/`):
- `SkylineDataSchema.cs`, `DocumentViewTransformer.cs`, `ColumnResolver.cs`
- `RowFactories.cs`, `SkylineRowSource.cs`, `Collections/SkylineObjectList.cs`,
  `Collections/NodeList.cs`
- `Entities/SkylineObject.cs`, `Entities/SkylineDocNode.cs`, `Entities/Protein.cs`,
  `Entities/Peptide.cs`, `Entities/Precursor.cs`, `Entities/Transition.cs`,
  `Entities/Result.cs`, `Entities/PeptideResult.cs`
- `Collections/ResultKey.cs`, `Collections/ResultMap.cs`, `Entities/ResultFile.cs`
- `RatioPropertyDescriptor.cs`, `AnnotationPropertyDescriptor.cs`
- `ReportSpecConverter.cs`, `ReportOrViewSpec.cs`

Related architecture:
- [architecture-data-model.md](architecture-data-model.md) — the immutable `SrmDocument`,
  `Results` arrays, and `Identity`/`GlobalIndex` that this layer reports on.
