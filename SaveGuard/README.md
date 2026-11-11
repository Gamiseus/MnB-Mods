# SaveGuard

Takes the place of the game's save serializer (`includes/ser.lua`, a small library file) with one that writes the same format but leaves out what a save does not need: particles, floating text, cues, clouds, and combat litter among the decals (casings, blood). Map decals such as mud, dirt and trenches are kept.

Saves from very long battles stay small, load faster, and no longer fail with `main function has more than 65536 constants`.

Because it replaces a whole file, another mod's patches on `includes/ser.lua` do not apply while this mod is on. QuarterMaster reports that as a note.
