"use strict";

const { ensureBinary } = require("./install");

if (process.env.CONTROLKEEL_SKIP_DOWNLOAD === "1") {
  process.exit(0);
}

ensureBinary({ forceDownload: true }).catch((error) => {
  console.error(error.message || error);
  process.exit(1);
});
