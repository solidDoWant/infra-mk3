// Inlines this repo's local> presets into the root Renovate config, in place.
// Renovate's local platform can't read local> presets (getRawFile returns
// null), so dry runs would otherwise silently drop them. Runs inside the
// Renovate image to use its json5.
//
// Usage: node inline-presets.mjs <repo dir>
import { createRequire } from "node:module";
import { readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";

const JSON5 = createRequire("/usr/local/renovate/")("json5");
const repo = process.argv[2];
const rootPath = join(repo, ".github/renovate.json5");
const read = (path) => JSON5.parse(readFileSync(path, "utf8"));

// Renovate's merge for these options: arrays concatenate, objects merge.
const merge = (base, child) => {
  for (const [key, value] of Object.entries(child)) {
    if (Array.isArray(base[key]) && Array.isArray(value)) {
      base[key] = [...base[key], ...value];
    } else if (isObject(base[key]) && isObject(value)) {
      base[key] = merge({ ...base[key] }, value);
    } else {
      base[key] = value;
    }
  }
  return base;
};
const isObject = (v) => v !== null && typeof v === "object" && !Array.isArray(v);

const root = read(rootPath);
const localPreset = /^local>[^/]+\/[^/]+\/\/(.+)$/;
// Presets resolve in extends order and the root's own settings apply last, so
// appending the local presets to the root body (after every remote preset)
// keeps the order as long as no remote preset follows a local one.
const local = root.extends.map((e) => e.match(localPreset)?.[1]);
const firstLocal = local.findIndex(Boolean);
if (firstLocal !== -1 && local.slice(firstLocal).some((p) => !p)) {
  throw new Error("a remote preset follows a local> preset; inlining would reorder them");
}

let inlined = { extends: root.extends.filter((_, i) => !local[i]) };
for (const path of local.filter(Boolean)) {
  const { $schema, description, ...preset } = read(join(repo, path));
  if (preset.extends) throw new Error(`${path}: nested extends aren't supported`);
  inlined = merge(inlined, preset);
}
const { extends: _, ...body } = root;
writeFileSync(rootPath, JSON.stringify(merge(inlined, body), null, 2));
