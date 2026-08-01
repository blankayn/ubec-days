import { readFile, writeFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import path from "node:path";

const toolsDirectory = path.dirname(fileURLToPath(import.meta.url));
const projectDirectory = path.dirname(toolsDirectory);
const templatePath = path.join(
  projectDirectory,
  "npc-studio-site",
  "public",
  "studio",
  "index.html",
);
const scriptPath = path.join(toolsDirectory, "npc_studio.js");
const outputPath = path.join(toolsDirectory, "psx_uc_npc_generator.html");

const [template, script] = await Promise.all([
  readFile(templatePath, "utf8"),
  readFile(scriptPath, "utf8"),
]);

const marker = '<script type="module" src="npc_studio.js"></script>';
if (!template.includes(marker)) {
  throw new Error("The studio template is missing its module-script marker.");
}

const standalone = template.replace(
  marker,
  `<script type="module">\n${script}\n  </script>`,
);

await writeFile(outputPath, standalone, "utf8");
console.log(`Built standalone NPC tool: ${outputPath}`);
