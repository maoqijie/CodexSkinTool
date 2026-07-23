fn main() {
    if codex_skin_tool_lib::run_background_helper_if_requested() {
        return;
    }
    codex_skin_tool_lib::run();
}
