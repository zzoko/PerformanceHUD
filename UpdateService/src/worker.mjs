// The deployed Worker: the published releases (written by publish_update.py from the live feed) and the handler.
import releases from "./releases.json" with { type: "json" };
import { createHandler } from "./handler.mjs";

export default createHandler(releases);
