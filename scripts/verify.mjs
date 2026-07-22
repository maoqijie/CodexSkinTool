import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import path from "node:path";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const windows = process.platform === "win32";
const cargo = windows ? "cargo.exe" : "cargo";
const npmTask = (args) =>
  windows
    ? [process.env.ComSpec ?? "cmd.exe", ["/d", "/s", "/c", `npm ${args.join(" ")}`]]
    : ["npm", args];

const tasks = [
  ["前端测试", ...npmTask(["run", "test"])],
  ["前端生产构建", ...npmTask(["run", "build"])],
  ["Rust 格式检查", cargo, ["fmt", "--manifest-path", "src-tauri/Cargo.toml", "--", "--check"]],
  ["Rust 编译检查", cargo, ["check", "--manifest-path", "src-tauri/Cargo.toml", "--all-targets"]],
  [
    "Rust Clippy",
    cargo,
    ["clippy", "--manifest-path", "src-tauri/Cargo.toml", "--all-targets", "--", "-D", "warnings"],
  ],
  ["Rust 测试", cargo, ["test", "--manifest-path", "src-tauri/Cargo.toml"]],
];

for (const [label, command, args] of tasks) {
  process.stdout.write(`\n==> ${label}\n`);
  const result = spawnSync(command, args, { cwd: root, stdio: "inherit" });
  if (result.error) {
    process.stderr.write(`${label}无法启动：${result.error.message}\n`);
    process.exit(1);
  }
  if (result.status !== 0) {
    process.exit(result.status ?? 1);
  }
}

process.stdout.write("\nPASS: Tauri 跨平台共享代码验证完成\n");
