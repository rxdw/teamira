/// Shared "this field was intentionally left out" marker for APIs that
/// tell "leave this field alone" apart from "set it to null" on an
/// `Object?`-typed optional parameter — see any of this constant's
/// callers for the actual pattern (DiaryService.updateEntry is the
/// original one; DiaryEntry.copyWith, DiaryRepository.updateEntry, and
/// DiaryStore.updateEntry all use it too).
///
/// One single instance, imported wherever it's needed, rather than each
/// file declaring its own private `const Object _unset = Object();` —
/// those wouldn't necessarily be `identical()` to each other, which
/// matters the moment one layer forwards a caller's "I left this out"
/// down into another layer that also uses this trick.
const Object unset = Object();
