// test_framework.mc — a project's test runner.
//
// `minc test` runs test/*.mc itself when a project has no build.mc: it
// compiles each one, runs it, times it, and reports. A project that has
// a build.mc gets the verb handed to the script instead, and the script
// owns all of it — finding the tests, the runner flags, and the record
// output an agent harness reads. This module is that work, so a build
// script calls it rather than writing it again:
//
//     import test_framework;
//     if str_equal(verb, "test") { return test_run_dir("test"); }
//
// A suite that is not one binary per file reports its own results:
//
//     TestRun r = test_begin();
//     test_report(&r, "parser", ok, test_ms_since(t0), "");
//     return test_finish(&r);
//
// Output follows MINC_AGENT, which the launcher sets: one JSON record
// per test when it reads "json", the plain PASS / FAIL lines otherwise.
// The runner flags are read from the command line: --filter <text>,
// --changed, --timeout <seconds>.

import process;
import file;
import str;

when os(windows) { str TEST_EXE_SUFFIX = ".exe"; }
else { str TEST_EXE_SUFFIX = ""; }

struct TestRun {
    i32 passed;
    i32 failed;
    i32 unchanged;    // skipped by --changed, nothing an edit reaches
    bool json;        // MINC_AGENT=json: records, not prose
}

// --- output ------------------------------------------------------------

private void _test_json_str(str s) {
    print("\"");
    for i32 i = 0; i < s.len; i++ {
        i32 c = cast(i32, s.data[i]);
        if c == 34 { print("\\\""); }
        else if c == 92 { print("\\\\"); }
        else if c == 10 { print("\\n"); }
        else if c == 13 { print("\\r"); }
        else if c == 9 { print("\\t"); }
        else if c < 32 {
            print("\\u00");
            str hex = "0123456789abcdef";
            print("{}", str_from(hex.data + ((c >> 4) & 15), 1));
            print("{}", str_from(hex.data + (c & 15), 1));
        }
        else { print("{}", str_from(s.data + i, 1)); }
    }
    print("\"");
    return;
}

// --- the runner's own flags, as the launcher spells them ----------------

// --filter <text>: only tests whose name holds the text.
str test_filter() {
    i32 argc = get_argc();
    for i32 i = 1; i + 1 < argc; i++ {
        if str_equal(str_from_cstr(get_arg(i)), "--filter") {
            return str_from_cstr(get_arg(i + 1));
        }
    }
    return "";
}

// --changed: skip a test no edit has reached since it last passed.
bool test_changed_only() {
    i32 argc = get_argc();
    for i32 i = 1; i < argc; i++ {
        if str_equal(str_from_cstr(get_arg(i)), "--changed") { return true; }
    }
    return false;
}

private i32 _test_parse_i32(str s) {
    i32 v = 0;
    for i32 i = 0; i < s.len; i++ {
        i32 c = cast(i32, s.data[i]);
        if c < 48 || c > 57 { return 0; }
        v = v * 10 + (c - 48);
    }
    return v;
}

// --timeout <seconds>, 0 when absent.
i32 test_timeout_s() {
    i32 argc = get_argc();
    for i32 i = 1; i + 1 < argc; i++ {
        if str_equal(str_from_cstr(get_arg(i)), "--timeout") {
            return _test_parse_i32(str_from_cstr(get_arg(i + 1)));
        }
    }
    return 0;
}

// The compiler to spawn: MINC names the install folder or the binary
// itself, then PATH. Empty when neither answers.
string test_compiler() {
    string env = env_get("MINC");
    if env.len > 0 {
        if path_is_dir(env) {
            string base = str_concat("minc", TEST_EXE_SUFFIX);
            defer free(base);
            string cand = path_join(env, base);
            free(env);
            return cand;
        }
        return env;
    }
    free(env);
    return path_which("minc");
}

// --- timing ------------------------------------------------------------

i64 test_now() { return qpc(); }

i64 test_ms_since(i64 t0) {
    i64 f = qpf();
    if f <= 0 { return 0; }
    return (qpc() - t0) * 1000 / f;
}

// --- reporting ---------------------------------------------------------

TestRun test_begin() {
    string mode = env_get("MINC_AGENT");
    defer free(mode);
    return TestRun{ .passed = 0, .failed = 0, .unchanged = 0,
                    .json = str_equal(str_from(mode.data, mode.len), "json") };
}

private void _test_emit(TestRun* r, str name, bool passed, i64 ms,
                        i32 exit_code, bool has_exit, bool timed_out, str output) {
    if passed { r.passed = r.passed + 1; }
    else { r.failed = r.failed + 1; }
    if r.json {
        print("{\"kind\":\"test\",\"name\":");
        _test_json_str(name);
        if passed { print(",\"status\":\"pass\""); }
        else { print(",\"status\":\"fail\""); }
        print(",\"ms\":{}", ms);
        if timed_out { print(",\"reason\":\"timeout\""); }
        else if has_exit { print(",\"exit\":{}", exit_code); }
        if output.len > 0 {
            print(",\"output\":");
            _test_json_str(output);
        }
        print("}\n");
        return;
    }
    if passed {
        print("  PASS  {}\n", name);
        return;
    }
    if timed_out { print("  FAIL  {} (timeout)\n", name); }
    else if has_exit { print("  FAIL  {} (exit {})\n", name, exit_code); }
    else { print("  FAIL  {}\n", name); }
    if output.len > 0 { print("{}", output); }
    return;
}

// One result. `output` is the test's own output, reported on a failure
// and carried in the record; pass an empty str when there is none.
void test_report(TestRun* r, str name, bool passed, i64 ms, str output) {
    _test_emit(r, name, passed, ms, 0, false, false, output);
    return;
}

// A failure carrying what the built-in runner records: the status the
// process returned, or that it ran out of time.
void test_report_fail(TestRun* r, str name, i64 ms, i32 exit_code,
                      bool timed_out, str output) {
    _test_emit(r, name, false, ms, exit_code, !timed_out, timed_out, output);
    return;
}

// A test skipped because no edit reached it since it last passed.
void test_report_unchanged(TestRun* r, str name) {
    r.unchanged = r.unchanged + 1;
    if r.json {
        print("{\"kind\":\"test\",\"name\":");
        _test_json_str(name);
        print(",\"status\":\"unchanged\"}\n");
    }
    return;
}

// The results line, and the process status: 1 when anything failed.
i32 test_finish(TestRun* r) {
    if r.json {
        print("{\"kind\":\"results\",\"passed\":{},\"failed\":{},\"unchanged\":{}}\n",
              r.passed, r.failed, r.unchanged);
    } else {
        print("{} passed, {} failed", r.passed, r.failed);
        if r.unchanged > 0 { print(", {} unchanged", r.unchanged); }
        print("\n");
    }
    if r.failed > 0 { return 1; }
    return 0;
}

// --- one test per file -------------------------------------------------

// True when a dependency is newer than the stamp the last pass wrote,
// so the test has to run again.
private bool _test_stale(str deps, str okf) {
    FileStamp ok = file_stamp(okf);
    if !ok.ok { return true; }
    FileData d = file_read(deps);
    if d.data == null { return true; }
    defer free(d.data);
    i32 n = cast(i32, d.len);
    i32 start = 0;
    for i32 i = 0; i <= n; i++ {
        if i == n || d.data[i] == 10 {
            i32 e = i;
            if e > start && d.data[e - 1] == 13 { e = e - 1; }
            if e > start {
                FileStamp s = file_stamp(str_from(d.data + start, e - start));
                if !s.ok || s.mtime >= ok.mtime { return true; }
            }
            start = i + 1;
        }
    }
    return false;
}

// Compile and run every `.mc` in `dir`, one process each, reporting as
// the mode asks. Returns the status for main: 1 when anything failed.
i32 test_run_dir(str dir) {
    if !path_is_dir(dir) {
        eprint("error: no {} directory here\n", dir);
        return 1;
    }
    string cc = test_compiler();
    defer free(cc);
    if cc.len == 0 {
        eprint("error: no minc compiler found (set MINC, or put one on PATH)\n");
        return 1;
    }
    string outdir = path_join("build", dir);
    defer free(outdir);
    ignore dir_create("build");
    ignore dir_create(outdir);

    str filter = test_filter();
    bool changed_only = test_changed_only();
    i32 timeout_s = test_timeout_s();

    DirList tests = dir_list_ext(dir, ".mc");
    defer dir_list_free(&tests);
    TestRun r = test_begin();

    for i32 i = 0; i < tests.count; i++ {
        str name = tests.items[i];
        str stem = path_stem(name);
        if filter.len > 0 && !str_contains(stem, filter) { continue; }

        string src = path_join(dir, name);
        defer free(src);
        string exe_base = str_concat(stem, TEST_EXE_SUFFIX);
        defer free(exe_base);
        string exe = path_join(outdir, exe_base);
        defer free(exe);
        string dep_base = str_concat(stem, ".d");
        defer free(dep_base);
        string deps = path_join(outdir, dep_base);
        defer free(deps);
        string ok_base = str_concat(stem, ".ok");
        defer free(ok_base);
        string okf = path_join(outdir, ok_base);
        defer free(okf);

        if changed_only && !_test_stale(deps, okf) {
            test_report_unchanged(&r, stem);
            continue;
        }
        ignore file_remove(okf);

        i64 t0 = test_now();
        ProcCmd c = {
            .args = { str_from(cc.data, cc.len), str_from(src.data, src.len),
                      "-o", str_from(exe.data, exe.len),
                      "--deps", str_from(deps.data, deps.len) },
            .capture = true
        };
        ProcResult cr = proc_run(&c);
        if cr.exit_code != 0 {
            test_report(&r, stem, false, test_ms_since(t0),
                        str_from(cr.out.data, cr.out.len));
            proc_result_free(&cr);
            continue;
        }
        proc_result_free(&cr);

        ProcCmd rc = { .args = { str_from(exe.data, exe.len) }, .capture = true };
        if timeout_s > 0 { proc_timeout(&rc, timeout_s * 1000); }
        ProcResult rr = proc_run(&rc);
        bool passed = !rr.timed_out && rr.exit_code == 0;
        i64 ms = test_ms_since(t0);
        str out = str_from(rr.out.data, rr.out.len);
        if passed {
            ignore file_write_str(okf, "");
            test_report(&r, stem, true, ms, out);
        } else {
            test_report_fail(&r, stem, ms, rr.exit_code, rr.timed_out, out);
        }
        proc_result_free(&rr);
    }
    return test_finish(&r);
}
