# TODO-20260129_nist_gethashcode_null.md

## Branch Information
- **Branch**: `Skyline/work/20260129_nist_gethashcode_null`
- **Base**: `master`
- **Created**: 2026-01-29
- **Status**: Complete
- **GitHub Issue**: [#3879](https://github.com/ProteoWizard/pwiz/issues/3879)
- **PR**: [#3906](https://github.com/ProteoWizard/pwiz/pull/3906)

## Objective
Fix NullReferenceException in NistLibraryBase.GetHashCode() when Id or Revision is null.

## Root Cause Analysis
`NistLibraryBase.GetHashCode()` at NistLibSpec.cs:2088 calls `Id.GetHashCode()` and `Revision.GetHashCode()` without null checks. These properties can be null when:
- The parameterless constructor is used for XML deserialization and the attributes are absent
- The regex in the parameterized constructor doesn't match

The existing `FilePath` property already had a null check, making Id and Revision inconsistent.

`Equals()` is already null-safe because it uses `object.Equals(object, object)` which handles nulls.

## Exception Details
- **Fingerprint**: `98ca2e1060fd3a89`
- **Reports**: 2 from 2 users (version 25.1.1.271)
- **Trigger**: User clicks replicate bar -> chromatogram update -> caching system computes hash -> crash

## Changes Made
- [x] Fixed GetHashCode() null safety - added null-conditional operators for Id, Revision, and FilePath (consistent style)
- [x] Verified Equals() is already null-safe (uses object.Equals static method)

## Files Modified
- `pwiz_tools/Skyline/Model/Lib/NistLibSpec.cs` - GetHashCode() at line 2093-2095

## Test Plan
A unit test could verify GetHashCode()/Equals() don't throw when Id/Revision are null. However, NistLibraryBase is abstract and its concrete subclass NistLibrary has a private parameterless constructor (for serialization). Testing would require XML deserialization to create an instance without Id/Revision attributes, or reflection.

The fix is a straightforward null-safety improvement (3 lines) with minimal risk.

## Implementation Notes
- Used null-conditional operator (`?.`) with null-coalescing (`?? 0`) for all three properties
- Made FilePath consistent with Id/Revision by switching from ternary to `?.` pattern
- No behavioral change for non-null values
