# ChromKey.FromId parses m/z out of a chromatogram ID that contains a comma

## Objective

`ChromKey.FromId` prefers m/z values parsed out of the chromatogram ID text over the ones the caller passes
in, whenever the ID splits into exactly two comma-separated parts. A waters_connect channel title can contain
a comma, and then the parse throws and the whole import fails.

Found by `/code-review max` on the #4346 branch (finding 14). It is **pre-existing**, unrelated to that
change, and was left out of it deliberately.

## The code

`pwiz_tools/Skyline/Model/Results/ChromHeaderInfo.cs`, `ChromKey.FromId`, roughly lines 2102-2136:

```csharp
mzs = mzPart.Split(new[] { ',' });
if (mzs.Length != 2 && (precursorMz == null || productMz == null))
    throw new InvalidDataException(...);        // only when the caller gave nothing to fall back on
...
if (mzs.Length == 2)
{
    precursor = double.Parse(mzs[0], CultureInfo.InvariantCulture);   // throws on non-numeric text
    product = double.Parse(mzs[1], CultureInfo.InvariantCulture);
}
else
{
    precursor = precursorMz.Value;             // the values the reader actually reported
    product = productMz.Value;
}
```

The two-part case is the Thermo ID format (`"SRM SIC 581.31,595.3"`). Any other ID with exactly one comma
takes the same branch, and `double.Parse` on the surrounding text throws `FormatException` - not the
`InvalidDataException` the method raises for an unusable ID, so it surfaces as an unexpected error.

## Reproducing

Real data on the waters_connect dev server (`devconnect.waters.com:48444`), folder
`Skyline/reader_waters_testdata`, sample set `HDMRM`, injection `HDMRM_Skyline_Short`, has this MRM channel:

```
Enter Name: 1: TOF MRM 445.1200>0 6eV, 4eV ESI+ (TIC)
```

`ChromatogramList_UNIFI::createIndex` turns that into the chromatogram ID
`+ SRM SIC Enter Name: 1: TOF MRM 445.1200>0 6eV, 4eV ESI+ (TIC)`, which `ChromKey.IsKeyId` accepts and
`FromId` then splits into two parts on the one comma. The same shape appears in the reader's own documentation
comment (`WatersConnectData.ipp`, the `/channels/mrm` sample JSON).

Not yet confirmed end to end by importing that injection - the failure is read off the code path.

## Tasks

- [ ] Confirm by importing `HDMRM_Skyline_Short` (or a converted mzML of it) into a document
- [ ] Prefer the caller's `precursorMz`/`productMz` when they are supplied, and parse the ID only as the
      fallback, rather than the other way round. Keep the Thermo two-part format working when no values are
      passed (`ChromatogramCache` reads old caches through the same method)
- [ ] Only parse the two-part form when both parts actually parse as numbers
- [ ] Unit test in `Test` over `ChromKey.FromId`: Thermo `"581.31,595.3"` with and without passed values, the
      waters_connect title above, and an ID with two or more commas

## Notes

Callers that pass the values: `ChromatogramDataProvider` (from `MsDataFileImpl.GetChromatogramMetadata`).
Callers that do not: cache reading paths. Both need to keep working.
