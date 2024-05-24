# offbeat 🎶
###### clap based plugin framework in nim

offbeat is mainly built around it managing parameters for you. simply define them initially, and it handles describing them to clap, events, saving, loading, etc. parameters can be float, int, or bool, with floats being the most fully featured, with built in smoothing.

there are numerous optional callbacks to shim in additional code, if needed, in many places. many are more theoretical, while others have a clear imagined use, like the calculate callback on smoothed float parameters, which has been added in large part to enable smooth but optimized filter coefficient calculation.

depends on [nim-clap](https://github.com/morganholly/nim-clap). `nimble install clap`

---

### features
- effect plugins
- parameters
- saving
- loading
- automation
- parameter smoothing

### planned features (no specific order, in progress marked with 🧪)
- synth plugins and other uses of midi input or output
  - possibly with a synth framework which handles voices and calls various callbacks when needed
- 🧪 custom ui
  - i intend to simply provide a sokol context for the user to supply mesh, shader, etc for
  - however i would like to create shaders that use SDFs to create uniform based tweaking of looks and mesh based value, size, etc, for something a bit easier to place controls for, along with a library to handle mapping events to callbacks
- save/load error correction
- preset system
  - optional json format for presets (no error correction)
- global settings system
- improve ergonomics of using parameter values
  - maybe using generated macros?
  - i think i have a functional name to index mapping table set up, but i have not tried it out. it would at least be less error prone than raw indices
- non-destructive modulation
- restructure offbeat into multiple files
  - clap bindings are now separated out
- separate the one big nimplugin.nim file into multiple smaller files
- set up tests

### plugins made with offbeat
- example2.nim (needs better name)
  - gain, channel flip, channel rotate. a slightly weird take on a utility/tool/whatever your daw calls this plugin

i would like to make more example plugins going forward, especially after i add synth support. the goal is to make plugins that are good enough to use and weird enough to stand out, rather than being the most boringest plugins you can think of. i think larger weird plugins will test the framework in unexpected ways and ensure it is working as expected.

### building
to build, run the following command
```
nim compile --out:"example2" --app:lib --threads:on ".../offbeat/example2.nim"
```
or for debugging
```
nim compile --verbosity:1 --hints:off --out:"example2" --app:lib --forceBuild
--threads:on --lineDir:on --lineTrace:on --debuginfo:on ".../offbeat/example2.nim"
```

#### mac
then copy the binary (and .dSYM if debugging) into the provided example2.clap bundle for macos. if you change the filename, you will need to change the bundle plist to have the updated name.

#### other platforms
i am not sure what is needed for windows or linux, but reaper at least doesn't care if it is bundled or not. i simply copied and modified the surge bundle.
