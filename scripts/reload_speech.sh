#!/bin/bash
set -euo pipefail
hs -t 4 -c 'if selectionTranslator then selectionTranslator.stop() end' </dev/null
# Allow an owned AV helper to acknowledge stop before replacing only this module.
python3 -c 'import time; time.sleep(0.7)'
hs -t 4 -c 'package.loaded.selection_translator=nil;package.loaded.selection_speech=nil;package.loaded.speech_logic=nil;selectionTranslator=require("selection_translator");local ok,err=selectionTranslator.start();assert(ok,err);print(hs.json.encode(selectionTranslator.status().speech or {legacySpeech=true}))' </dev/null
