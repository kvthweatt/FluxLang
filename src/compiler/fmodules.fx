// Author: Karac V. Thweatt
//
// fmodules.fx - module system (port of fmodules.py)
//
// A module is a named group of declarations with a build block:
//
//     module Main
//     {
//         from "logging.fx";
//         def main() -> int { ... };
//     }
//     # build
//     {
//         #[entrypoint] = this,
//         #[target] = executable,
//         !+#[effect_check] = true,
//         #[override for {Logging}] = { #[borrow_check] = true },
//     };
//
// This pass runs after parsing. It pulls every module reachable through 'from' into one
// compilation unit, resolves the build settings of each module, and flattens the module
// bodies into the program's statement list so the rest of the compiler sees an ordinary
// program.
//
// Settings (tag, default):
//     entrypoint   'this' marks an entry module of the target file
//     name         module name   output name (entry module)
//     target       executable    bootloader | executable | compact | library | driver
//     debug        false         Debug instead of Release output folder
//     borrow_check false         report borrow violations for this module's code
//     effect_check false         report effect violations for this module's code
//     dce          true          false keeps every declaration of the module alive
//     using        {}            namespaces made visible to the module's code
//     platform     {}            platforms the module builds for (empty = any)
//
// A module's own entries set its settings. '#[override for {M}] = { ... }' in another
// module overrides M's settings as M is built into this target, unless M locked the tag
// with '!+'. The module closest to the entry wins when several override the same tag.
// The command line can only switch checks on: --borrowcheck and --effects force the check
// for every module, including modules that lock it to false.
//
// Modules that share the entry's file but are not reached through 'from' are visible to
// the entry but are not part of its module graph: their checks do not run in this build.

#ifndef FLUX_STANDARD
#import <standard.fx>;
#endif;

#import <runtime/ffifio.fx>;

#ifndef FLUX_LEXER
#import "flexer.fx";
#endif;

#ifndef FLUX_PREPROCESSOR
#import "fpreprocess.fx";
#endif;

#ifndef FLUX_AST
#import "fast.fx";
#endif;

#ifndef FLUX_PARSER
#import "fparser.fx";
#endif;

#ifndef FLUX_BORROW
#import "fborrow.fx";
#endif;

#ifndef FLUX_MODULES
#def FLUX_MODULES 1;

using flux::lexer;
using flux::preprocessor;
using flux::ast;
using flux::parser;
using flux::types;
using flux::borrow;

namespace flux
{
    namespace modules
    {
        struct ModInfo
        {
            Node* node;
            byte* name, file, target, oname;
            PtrVec* deps;         // byte* module names pulled with 'from'
            PtrVec* locked;       // byte* tags locked with '!+'
            PtrVec* using_ns;     // byte*
            PtrVec* platform;     // byte*
            PtrVec* requires;     // byte* module names named by '#[requires]'
            bool borrow_check, effect_check, dce, debug, entry;
            bool expect_build_fail;   // '#[test] = { #[expect_build_fail] }'
            bool imported;        // declared in a file reached through 'from'
        };

        struct ModUnit
        {
            PtrVec* mods;         // ModInfo*
            PtrVec* order;        // ModInfo*, dependencies first
            PtrVec* programs;     // byte* names of the root modules that can be built as programs
            NameMap* files;       // path to PtrVec* of module names
            ModInfo* entry;
            byte* err;            // set when a pass failed
            PtrVec* warnings;     // byte* non-fatal notes for the driver to print
            NameMap* unbuilt;     // function name to the module declaring it, for modules not in this build
            byte* root_file, srcdir;
        };

        // ------------------------------------------------------------------
        // small helpers
        // ------------------------------------------------------------------

        mu_has(PtrVec* v, byte* s) -> bool
        {
            int i;
            if (v == (PtrVec*)0) { -> false; };
            while (i < v.len)
            {
                if (cstr_eq((byte*)v.items[i], s)) { -> true; };
                i++;
            };
            -> false;
        };

        mu_find(ModUnit* u, byte* name) -> ModInfo*
        {
            int i;
            ModInfo* m;
            while (i < u.mods.len)
            {
                m = (ModInfo*)u.mods.items[i];
                if (cstr_eq(m.name, name)) { -> m; };
                i++;
            };
            -> (ModInfo*)0;
        };

        mu_in_order(ModUnit* u, ModInfo* m) -> bool
        {
            int i;
            while (i < u.order.len)
            {
                if ((ModInfo*)u.order.items[i] == m) { -> true; };
                i++;
            };
            -> false;
        };

        mu_fail(ModUnit* u, byte* msg) -> byte*
        {
            u.err = msg;
            -> msg;
        };

        mu_has_modules(Node* prog) -> bool
        {
            int i;
            int c = node_count(prog, 0);
            while (i < c)
            {
                if (node_child(prog, 0, i).kind == NodeKind.MODULE_DEF) { -> true; };
                i++;
            };
            -> false;
        };

        // directory part of a file path, including the trailing separator, or ""
        mu_dir(byte* file) -> byte*
        {
            int i, k;
            int last = -1;
            byte* d;
            while (file[i] != 0)
            {
                if (file[i] == '/' | file[i] == '\\') { last = i; };
                i++;
            };
            d = (byte*)fmalloc((u64)(last + 2));
            k = 0;
            while (k <= last)
            {
                d[k] = file[k];
                k++;
            };
            d[k] = 0;
            -> d;
        };

        mu_exists(byte* p) -> bool
        {
            void* f = fopen(p, g"rb\0");
            if (f == (void*)0) { -> false; };
            fclose(f);
            -> true;
        };

        mu_is_abs(byte* p) -> bool
        {
            if (p[0] == '/' | p[0] == '\\') { -> true; };
            if (p[0] != 0 & p[1] == ':') { -> true; };
            -> false;
        };

        // A 'from' path is relative to the file that names it, then to the working directory.
        // Null when the file is not found.
        mu_resolve_path(byte* spec, byte* from_file) -> byte*
        {
            byte* cand;
            if (mu_is_abs(spec))
            {
                if (mu_exists(spec)) { -> ts_dup(spec); };
                -> (byte*)0;
            };
            cand = join3_f(mu_dir(from_file), g"\0", spec, 1);
            if (mu_exists(cand)) { -> cand; };
            ffree(cand);
            if (mu_exists(spec)) { -> ts_dup(spec); };
            -> (byte*)0;
        };

        // value of the last scalar entry with the given tag (not an override), or null
        mu_tag_entry(Node* m, byte* tag) -> Node*
        {
            int i;
            int c = node_count(m, 2);
            Node* e, found;
            while (i < c)
            {
                e = node_child(m, 2, i);
                if (e.ival != 3 & cstr_eq(e.text, tag)) { found = e; };
                i++;
            };
            -> found;
        };

        mu_defines(Node* m, byte* fn) -> bool
        {
            int i;
            int c = node_count(m, 0);
            Node* f;
            while (i < c)
            {
                f = bc_unwrap_fn(node_child(m, 0, i));
                if (f.kind == NodeKind.FUNCTION_DEF)
                {
                    if (cstr_eq(f.text, fn)) { -> true; };
                };
                i++;
            };
            -> false;
        };

        // ------------------------------------------------------------------
        // loading
        // ------------------------------------------------------------------

        // Parses another source file. Returns the program, or null with *err set.
        // The lexer and parser data are never freed: the nodes borrow from them.
        mu_parse_file(byte* path, byte* srcdir, byte** err) -> Node*
        {
            Preprocessor pp(path);
            Node* prog;
            pp.verbose = false;
            if (srcdir != (byte*)0) { pp.set_srcdir(srcdir); };
            pp.add_default_macros();
            if (!pp.process())
            {
                *err = join3_f(g"from \"\0", path, join3(g"\": preprocessor error: \0", pp.err_text(), g"\0"), 4);
                -> (Node*)0;
            };
            byte* src = pp.text_ptr();
            int len = pp.text_len();
            Lexer lx(src, len);
            if (!lx.tokenize())
            {
                *err = join3(g"from \"\0", path, g"\": lexer error\0");
                -> (Node*)0;
            };
            Parser ps(@lx);
            ps.st = st_new();
            ps.lmap = pp.map_line.arr;
            ps.lmapn = pp.map_line.len;
            ps.lfiles = pp.line_files();
            prog = ps.parse();
            if (ps.failed)
            {
                Buf perr;
                perr.__init();
                switch (ps.err_kind != ParseErr.SILENT) { case (true) { ps.render_error(@perr); println(perr.mem); } default {}; };
                perr.__exit();
                *err = join3(g"from \"\0", path, g"\": parse error\0");
                -> (Node*)0;
            };
            -> prog;
        };

        mu_new_info(Node* m, byte* file, bool imported) -> ModInfo*
        {
            ModInfo* mi = (ModInfo*)fmalloc((u64)((sizeof(ModInfo) + 7) / 8));
            mi
            {
                .node = m;
                .name = m.text;
                .file = file;
                .target = g"executable\0";
                .oname = m.text;
                .deps = pv_new();
                .locked = pv_new();
                .using_ns = pv_new();
                .platform = pv_new();
                .requires = pv_new();
                .borrow_check = false;
                .effect_check = false;
                .dce = true;
                .debug = false;
                .expect_build_fail = false;
                .entry = false;
                .imported = imported;
            };
            m.text2 = file;
            -> mi;
        };

        // Registers module m of file. Returns an error text or null.
        mu_add(ModUnit* u, Node* m, byte* file, bool imported) -> byte*
        {
            ModInfo* old = mu_find(u, m.text);
            if (old != (ModInfo*)0)
            {
                if (!cstr_eq(old.file, file))
                {
                    -> join3_f(join3(g"module '\0", m.text, g"' is declared in both \0"), old.file, join3(g" and \0", file, g"\0"), 5);
                };
                -> (byte*)0;
            };
            pv_push(u.mods, (void*)mu_new_info(m, file, imported));
            -> (byte*)0;
        };

        // Depth first: dependencies are ordered before their dependents.
        mu_visit(ModUnit* u, ModInfo* info, PtrVec* loading) -> byte*
        {
            int i, j;
            Node* fnode, prog, m;
            byte* path, err;
            bool kept;
            PtrVec* names;
            ModInfo* dep;
            if (mu_has(loading, info.name))
            {
                byte* chain = ts_dup(g"\0");
                i = 0;
                while (i < loading.len)
                {
                    chain = join3_f(chain, (byte*)loading.items[i], g" -> \0", 1);
                    i++;
                };
                -> join3_f(g"modules depend on each other: \0", chain, info.name, 2);
            };
            if (mu_in_order(u, info)) { -> (byte*)0; };
            pv_push(loading, (void*)info.name);
            i = 0;
            while (i < node_count(info.node, 1))
            {
                fnode = node_child(info.node, 1, i);
                i++;
                path = mu_resolve_path(fnode.text, info.file);
                if (path == (byte*)0)
                {
                    -> join3_f(join3(g"from \"\0", fnode.text, g"\": file not found (looked in \0"),
                                 mu_dir(info.file), g"and the working directory)\0", 3);
                };
                kept = false;
                if (!nm_has(u.files, path))
                {
                    err = (byte*)0;
                    prog = mu_parse_file(path, u.srcdir, @err);
                    if (prog == (Node*)0)
                    {
                        ffree(path);
                        -> err;
                    };
                    kept = true;
                    names = pv_new();
                    j = 0;
                    while (j < node_count(prog, 0))
                    {
                        m = node_child(prog, 0, j);
                        j++;
                        if (m.kind != NodeKind.MODULE_DEF) { continue; };
                        err = mu_add(u, m, path, true);
                        if (err != (byte*)0)
                        {
                            pv_free(names);
                            -> err;
                        };
                        pv_push(names, (void*)m.text);
                    };
                    if (names.len == 0)
                    {
                        pv_free(names);
                        -> join3(g"from \"\0", fnode.text, g"\": the file declares no module\0");
                    };
                    nm_put(u.files, path, (void*)names);
                };
                names = (PtrVec*)nm_get(u.files, path);
                // the module infos keep the path of a file this call parsed; any other copy is dropped
                if (!kept) { ffree(path); };
                j = 0;
                while (j < names.len)
                {
                    if (!mu_has(info.deps, (byte*)names.items[j])) { pv_push(info.deps, names.items[j]); };
                    dep = mu_find(u, (byte*)names.items[j]);
                    err = mu_visit(u, dep, loading);
                    if (err != (byte*)0) { -> err; };
                    j++;
                };
            };
            // '#[requires] = {A, B}': the other modules this one uses
            Node* rq = mu_tag_entry(info.node, g"requires\0");
            if (rq != (Node*)0)
            {
                if (rq.ival != 2)
                {
                    -> join3(g"module '\0", info.name, g"': '#[requires]' takes a list: {A, B}\0");
                };
                i = 0;
                byte* rname;
                while (i < node_count(rq, 0))
                {
                    rname = node_child(rq, 0, i).text;
                    i++;
                    if (cstr_eq(rname, info.name))
                    {
                        -> join3(g"module '\0", info.name, g"' cannot require itself\0");
                    };
                    dep = mu_find(u, rname);
                    if (dep == (ModInfo*)0)
                    {
                        -> join3_f(join3(g"module '\0", info.name, g"': '#[requires]' names module '\0"),
                                 rname, g"', which is not declared in this file or pulled in with 'from'\0", 1);
                    };
                    if (!mu_has(info.deps, rname)) { pv_push(info.deps, (void*)rname); };
                    err = mu_visit(u, dep, loading);
                    if (err != (byte*)0) { -> err; };
                };
            };
            loading.len = loading.len - 1;
            pv_push(u.order, (void*)info);
            -> (byte*)0;
        };

        // Collects the modules of the root file and everything they pull in with 'from'.
        // On failure u.err is set. select, when not null, names the program to build.
        mu_load(Node* prog, byte* root_file, byte* select, byte* entry_fn, byte* srcdir) -> ModUnit*
        {
            ModUnit* u = (ModUnit*)fmalloc((u64)((sizeof(ModUnit) + 7) / 8));
            PtrVec* root = pv_new();
            PtrVec* marked = pv_new();
            PtrVec* loading = pv_new();
            defer pv_free(root);
            defer pv_free(marked);
            defer pv_free(loading);
            Node* m, t;
            byte* err;
            ModInfo* ei;
            int i;
            u
            {
                .mods = pv_new();
                .order = pv_new();
                .programs = pv_new();
                .files = nm_new();
                .entry = (ModInfo*)0;
                .err = (byte*)0;
                .warnings = pv_new();
                .unbuilt = nm_new();
                .root_file = root_file;
                .srcdir = srcdir;
            };

            i = 0;
            while (i < node_count(prog, 0))
            {
                m = node_child(prog, 0, i);
                i++;
                if (m.kind == NodeKind.MODULE_DEF) { pv_push(root, (void*)m); };
            };
            i = 0;
            while (i < root.len)
            {
                m = (Node*)root.items[i];
                i++;
                err = mu_add(u, m, root_file, false);
                if (err != (byte*)0) { mu_fail(u, err); -> u; };
                t = mu_tag_entry(m, g"entrypoint\0");
                if (t != (Node*)0)
                {
                    if (t.text2 != (byte*)0)
                    {
                        if (cstr_eq(t.text2, g"this\0")) { pv_push(marked, (void*)m.text); };
                    };
                };
            };
            i = 0;
            while (i < root.len)
            {
                m = (Node*)root.items[i];
                i++;
                if (mu_has(marked, m.text) | mu_defines(m, entry_fn)) { pv_push(u.programs, (void*)m.text); };
            };
            if (u.programs.len == 0)
            {
                mu_fail(u, join3_f(join3(g"no module in \0", root_file, g" defines \0"), entry_fn, g"() or sets '#[entrypoint] = this'\0", 1));
                -> u;
            };
            if (select != (byte*)0)
            {
                if (!mu_has(u.programs, select))
                {
                    mu_fail(u, join3(g"module '\0", select, g"' is not a program of this file\0"));
                    -> u;
                };
                ei = mu_find(u, select);
            }
            elif (marked.len > 0)
            {
                ei = mu_find(u, (byte*)marked.items[0]);
            }
            else
            {
                ei = mu_find(u, (byte*)u.programs.items[0]);
            };
            ei.entry = true;
            u.entry = ei;
            // only what the entry requires or pulls in is built
            err = mu_visit(u, ei, loading);
            if (err != (byte*)0) { mu_fail(u, err); -> u; };
            -> u;
        };

        // ------------------------------------------------------------------
        // settings
        // ------------------------------------------------------------------

        mu_known_tag(byte* t) -> bool
        {
            -> cstr_eq(t, g"entrypoint\0") | cstr_eq(t, g"name\0") | cstr_eq(t, g"target\0")
                 | cstr_eq(t, g"debug\0") | cstr_eq(t, g"borrow_check\0") | cstr_eq(t, g"effect_check\0")
                 | cstr_eq(t, g"dce\0") | cstr_eq(t, g"using\0") | cstr_eq(t, g"platform\0")
                 | cstr_eq(t, g"requires\0") | cstr_eq(t, g"test\0");
        };

        mu_is_bool_tag(byte* t) -> bool
        {
            -> cstr_eq(t, g"borrow_check\0") | cstr_eq(t, g"effect_check\0")
                 | cstr_eq(t, g"dce\0") | cstr_eq(t, g"debug\0");
        };

        mu_is_target(byte* t) -> bool
        {
            -> cstr_eq(t, g"bootloader\0") | cstr_eq(t, g"executable\0") | cstr_eq(t, g"compact\0")
                 | cstr_eq(t, g"library\0") | cstr_eq(t, g"driver\0");
        };

        mu_list_of(Node* e) -> PtrVec*
        {
            PtrVec* v = pv_new();
            int i;
            while (i < node_count(e, 0))
            {
                pv_push(v, (void*)node_child(e, 0, i).text);
                i++;
            };
            -> v;
        };

        // Stores entry e as a setting of mi. Returns an error text or null.
        mu_apply(ModInfo* mi, Node* e) -> byte*
        {
            byte* tag = e.text;
            if (mu_is_bool_tag(tag))
            {
                if (e.ival != 1) { -> join3_f(join3(g"module '\0", mi.name, g"': '#[\0"), tag, g"]' takes true or false\0", 1); };
                bool v = e.op != 0;
                if (cstr_eq(tag, g"borrow_check\0")) { mi.borrow_check = v; }
                elif (cstr_eq(tag, g"effect_check\0")) { mi.effect_check = v; }
                elif (cstr_eq(tag, g"dce\0")) { mi.dce = v; }
                else { mi.debug = v; };
                -> (byte*)0;
            };
            if (cstr_eq(tag, g"test\0"))
            {
                if (e.ival != 4) { -> join3_f(join3(g"module '\0", mi.name, g"': '#[test]' takes a block: = { #[subtag] }\0"), g"\0", g"\0", 1); };
                bool ebf = false;
                int ti2 = 0;
                Node* se;
                while (ti2 < node_count(e, 1))
                {
                    se = node_child(e, 1, ti2);
                    ti2++;
                    if (!cstr_eq(se.text, g"expect_build_fail\0"))
                    {
                        -> join3_f(join3(g"module '\0", mi.name, g"': unknown test tag '#[\0"), se.text,
                                     g"]' in '#[test]' (known: expect_build_fail)\0", 1);
                    };
                    if (se.ival != 1)
                    {
                        -> join3_f(join3(g"module '\0", mi.name, g"': '#[test]' subtag '#[\0"), se.text,
                                     g"]' takes true or false\0", 1);
                    };
                    ebf = se.op != 0;
                };
                mi.expect_build_fail = ebf;
                -> (byte*)0;
            };
            if (cstr_eq(tag, g"using\0") | cstr_eq(tag, g"platform\0") | cstr_eq(tag, g"requires\0"))
            {
                if (e.ival != 2) { -> join3_f(join3(g"module '\0", mi.name, g"': '#[\0"), tag, g"]' takes a list: {A, B}\0", 1); };
                if (cstr_eq(tag, g"using\0")) { pv_free(mi.using_ns); mi.using_ns = mu_list_of(e); }
                elif (cstr_eq(tag, g"requires\0")) { pv_free(mi.requires); mi.requires = mu_list_of(e); }
                else { pv_free(mi.platform); mi.platform = mu_list_of(e); };
                -> (byte*)0;
            };
            if (e.ival != 0 | e.text2 == (byte*)0)
            {
                -> join3_f(join3(g"module '\0", mi.name, g"': '#[\0"), tag, g"]' takes a single name\0", 1);
            };
            if (cstr_eq(tag, g"name\0")) { mi.oname = e.text2; }
            else { mi.target = e.text2; };
            -> (byte*)0;
        };

        mu_lower_eq(byte* a, byte* b) -> bool
        {
            int i;
            byte x, y;
            while (a[i] != 0 & b[i] != 0)
            {
                x = a[i];
                y = b[i];
                if (x >= 'A' & x <= 'Z') { x = (byte)(x + 32); };
                if (y >= 'A' & y <= 'Z') { y = (byte)(y + 32); };
                if (x != y) { -> false; };
                i++;
            };
            -> a[i] == 0 & b[i] == 0;
        };

        // Fills in the settings of every module of the unit. Returns an error text or null.
        mu_resolve_settings(ModUnit* u, bool cli_borrow, bool cli_effects, byte* platform) -> byte*
        {
            int i, j, k, q;
            Node* e, oe, t;
            ModInfo* mi, ti, cur;
            byte* err, key;
            NameMap* applied = nm_new();
            PtrVec* queue = pv_new();
            PtrVec* seen = pv_new();
            defer nm_free(applied);
            defer pv_free(queue);
            defer pv_free(seen);
            bool found;

            i = 0;
            while (i < u.order.len)
            {
                mi = (ModInfo*)u.order.items[i];
                i++;
                j = 0;
                while (j < node_count(mi.node, 2))
                {
                    e = node_child(mi.node, 2, j);
                    j++;
                    if (e.ival == 3) { continue; };
                    if (!mu_known_tag(e.text))
                    {
                        -> join3_f(join3(g"module '\0", mi.name, g"': unknown build tag '#[\0"), e.text, g"]'\0", 1);
                    };
                    if (cstr_eq(e.text, g"entrypoint\0")) { continue; };
                    err = mu_apply(mi, e);
                    if (err != (byte*)0) { -> err; };
                    if ((e.flags `& 1) != 0) { pv_push(mi.locked, (void*)e.text); };
                };
                if (!mu_is_target(mi.target))
                {
                    -> join3_f(join3(g"module '\0", mi.name, g"': '#[target] = \0"), mi.target,
                                 g"' is not one of bootloader, executable, compact, library, driver\0", 1);
                };
            };

            // overrides: breadth first from the entry, so the module nearest the entry wins
            pv_push(queue, (void*)u.entry);
            pv_push(seen, (void*)u.entry);
            q = 0;
            while (q < queue.len)
            {
                cur = (ModInfo*)queue.items[q];
                q++;
                j = 0;
                while (j < node_count(cur.node, 2))
                {
                    e = node_child(cur.node, 2, j);
                    j++;
                    if (e.ival != 3) { continue; };
                    k = 0;
                    while (k < node_count(e, 2))
                    {
                        t = node_child(e, 2, k);
                        k++;
                        ti = mu_find(u, t.text);
                        if (ti == (ModInfo*)0)
                        {
                            -> join3_f(join3(g"module '\0", cur.name, g"': '#[override for {\0"), t.text,
                                         g"}]' names a module that is not part of this build\0", 1);
                        };
                        if (!mu_has(cur.deps, t.text))
                        {
                            -> join3_f(join3(g"module '\0", cur.name, g"': cannot override module '\0"), t.text,
                                     join3_f(join3(g"' because '\0", cur.name, g"' does not use it. Add '#[requires] = {\0"),
                                           t.text, join3(g"}' to the build settings of '\0", cur.name, g"' first\0"), 5), 5);
                        };
                        i = 0;
                        while (i < node_count(e, 1))
                        {
                            oe = node_child(e, 1, i);
                            i++;
                            if (!mu_known_tag(oe.text) | cstr_eq(oe.text, g"entrypoint\0"))
                            {
                                -> join3_f(join3(g"module '\0", cur.name, g"': cannot override '#[\0"), oe.text, g"]'\0", 1);
                            };
                            key = join3(t.text, g":\0", oe.text);
                            if (mu_has(ti.locked, oe.text))
                            {
                                pv_push(u.warnings, (void*)join3_f(join3_f(join3(g"module '\0", cur.name, g"': '#[override for {\0"), t.text,
                                    join3(g"}]' sets '#[\0", oe.text, g"]', but module '\0"), 5),
                                    ti.name, g"' locked it with '!+'; the override is ignored\0", 1));
                                ffree(key);
                                continue;
                            };
                            if (nm_has(applied, key))
                            {
                                ffree(key);
                                continue;
                            };
                            err = mu_apply(ti, oe);
                            if (err != (byte*)0)
                            {
                                ffree(key);
                                -> err;
                            };
                            nm_put(applied, key, (void*)1);
                            ffree(key);
                        };
                    };
                };
                j = 0;
                while (j < cur.deps.len)
                {
                    ti = mu_find(u, (byte*)cur.deps.items[j]);
                    j++;
                    found = false;
                    k = 0;
                    while (k < seen.len)
                    {
                        if ((ModInfo*)seen.items[k] == ti) { found = true; };
                        k++;
                    };
                    if (!found)
                    {
                        pv_push(seen, (void*)ti);
                        pv_push(queue, (void*)ti);
                    };
                };
            };

            i = 0;
            byte* plist;
            while (i < u.order.len)
            {
                mi = (ModInfo*)u.order.items[i];
                i++;
                if (cli_borrow) { mi.borrow_check = true; };
                if (cli_effects) { mi.effect_check = true; };
                if (mi.platform.len > 0 & platform != (byte*)0)
                {
                    found = false;
                    k = 0;
                    while (k < mi.platform.len)
                    {
                        if (mu_lower_eq((byte*)mi.platform.items[k], platform)) { found = true; };
                        k++;
                    };
                    if (!found)
                    {
                        plist = ts_dup(g"\0");
                        k = 0;
                        while (k < mi.platform.len)
                        {
                            if (k > 0) { plist = join3_f(plist, g", \0", g"\0", 1); };
                            plist = join3_f(plist, (byte*)mi.platform.items[k], g"\0", 1);
                            k++;
                        };
                        -> join3_f(join3(g"module '\0", mi.name, g"' builds for {\0"), plist,
                                     join3(g"} but this build targets \0", platform, g"\0"), 7);
                    };
                };
            };
            -> (byte*)0;
        };

        // ------------------------------------------------------------------
        // flattening
        // ------------------------------------------------------------------

        // smallest and largest line of the statements below n
        mu_line_range(Node* n, int* mn, int* mx) -> void
        {
            int s, i, c;
            if (n == (Node*)0) { ->; };
            if (n.line > 0)
            {
                if (n.line < *mn) { *mn = n.line; };
                if (n.line > *mx) { *mx = n.line; };
            };
            mu_line_range(n.a, mn, mx);
            mu_line_range(n.b, mn, mx);
            mu_line_range(n.c, mn, mx);
            mu_line_range(n.d, mn, mx);
            mu_line_range(n.e, mn, mx);
            s = 0;
            while (s < 6)
            {
                c = node_count(n, s);
                i = 0;
                while (i < c)
                {
                    mu_line_range(node_child(n, s, i), mn, mx);
                    i++;
                };
                s++;
            };
            ->;
        };

        mu_shift_lines(Node* n, int d) -> void
        {
            int s, i, c;
            if (n == (Node*)0) { ->; };
            if (n.line > 0) { n.line = n.line + d; };
            mu_shift_lines(n.a, d);
            mu_shift_lines(n.b, d);
            mu_shift_lines(n.c, d);
            mu_shift_lines(n.d, d);
            mu_shift_lines(n.e, d);
            s = 0;
            while (s < 6)
            {
                c = node_count(n, s);
                i = 0;
                while (i < c)
                {
                    mu_shift_lines(node_child(n, s, i), d);
                    i++;
                };
                s++;
            };
            ->;
        };

        // "a.b" and "a::b" become the mangled form "a__b" the using statements carry
        mu_mangle_ns(byte* ns) -> byte*
        {
            int i, n, k;
            byte* r;
            while (ns[n] != 0) { n++; };
            r = (byte*)fmalloc((u64)(n * 2 + 2));
            while (ns[i] != 0)
            {
                if (ns[i] == '.')
                {
                    r[k] = '_';
                    r[k + 1] = '_';
                    k = k + 2;
                    i++;
                }
                elif (ns[i] == ':' & ns[i + 1] == ':')
                {
                    r[k] = '_';
                    r[k + 1] = '_';
                    k = k + 2;
                    i = i + 2;
                }
                else
                {
                    r[k] = ns[i];
                    k++;
                    i++;
                };
            };
            r[k] = 0;
            -> r;
        };

        // True when a module of this build declares a function called name
        mu_built_defines(ModUnit* u, byte* name) -> bool
        {
            int i;
            while (i < u.order.len)
            {
                if (mu_defines(((ModInfo*)u.order.items[i]).node, name)) { -> true; };
                i++;
            };
            -> false;
        };

        // Replaces the module declarations of the program by their contents, dependencies
        // first. Statements that are not modules (the root file's imports and globals) stay in
        // front. Each module's 'using' list becomes using statements in front of its body.
        // The typer sees a function only from lines after its declaration, so a module whose
        // lines do not follow the statements before it is moved down to follow them.
        mu_flatten(Node* prog, ModUnit* u, byte* entry_fn) -> void
        {
            NodeVec* nv = nv_new();
            ModInfo* mi;
            Node* s, f, us;
            int i, j, c, mn, mx, top, mtop;

            c = node_count(prog, 0);
            i = 0;
            while (i < c)
            {
                s = node_child(prog, 0, i);
                i++;
                if (s.kind == NodeKind.MODULE_DEF) { continue; };
                nv_push(nv, s);
                mn = 2147483647;
                mx = 0;
                mu_line_range(s, @mn, @mx);
                if (mx > top) { top = mx; };
            };

            i = 0;
            NodeVec* kept;
            while (i < u.order.len)
            {
                mi = (ModInfo*)u.order.items[i];
                i++;
                // only the entry module contributes the program's main
                if (!mi.entry)
                {
                    kept = nv_new();
                    j = 0;
                    c = node_count(mi.node, 0);
                    while (j < c)
                    {
                        s = node_child(mi.node, 0, j);
                        j++;
                        f = bc_unwrap_fn(s);
                        if (f.kind == NodeKind.FUNCTION_DEF & cstr_eq(f.text, entry_fn)) { continue; };
                        nv_push(kept, s);
                    };
                    mi.node.l0 = kept;
                };
                mn = 2147483647;
                mx = 0;
                mu_line_range(mi.node, @mn, @mx);
                if (mx == 0) { mn = top + 1; mx = top + 1; };
                if (mn <= top)
                {
                    mu_shift_lines(mi.node, top - mn + 1);
                    mx = mx + (top - mn + 1);
                };
                mtop = mx;
                j = 0;
                while (j < mi.using_ns.len)
                {
                    us = node_new(NodeKind.USING_STATEMENT, mi.node.line, mi.node.col);
                    us.text = mu_mangle_ns((byte*)mi.using_ns.items[j]);
                    nv_push(nv, us);
                    j++;
                };
                c = node_count(mi.node, 0);
                j = 0;
                while (j < c)
                {
                    nv_push(nv, node_child(mi.node, 0, j));
                    j++;
                };
                if (mtop > top) { top = mtop; };
            };
            prog.l0 = nv;

            // Functions of modules that are declared but not part of this build. A call to one of
            // them that finds nothing is reported with the module to require.
            i = 0;
            while (i < u.mods.len)
            {
                mi = (ModInfo*)u.mods.items[i];
                i++;
                if (mu_in_order(u, mi)) { continue; };
                c = node_count(mi.node, 0);
                j = 0;
                while (j < c)
                {
                    f = bc_unwrap_fn(node_child(mi.node, 0, j));
                    j++;
                    if (f.kind != NodeKind.FUNCTION_DEF) { continue; };
                    if (nm_has(u.unbuilt, f.text)) { continue; };
                    if (mu_built_defines(u, f.text)) { continue; };
                    nm_put(u.unbuilt, f.text, (void*)mi.name);
                };
            };
            ->;
        };

        // ------------------------------------------------------------------
        // per-module attribution of functions
        // ------------------------------------------------------------------

        struct ModMap
        {
            BcOwners* own;
            NameMap* on_borrow; // module name to 1 when its borrow check is on
            NameMap* on_effect;
        };

        // Frees what mu_load and the passes after it allocated. The nodes belong to the program
        // and the module names to the nodes; the file names of imported modules, one text per file
        // shared by that file's modules, belong to the unit.
        mu_free(ModUnit* u) -> void
        {
            int i, k;
            ModInfo* mi;
            ModInfo* pm;
            bool seen;
            if (u == (ModUnit*)0) { ->; };
            while (i < u.mods.len)
            {
                mi = (ModInfo*)u.mods.items[i];
                if (mi.imported)
                {
                    seen = false;
                    k = 0;
                    while (k < i)
                    {
                        pm = (ModInfo*)u.mods.items[k];
                        if (pm.file == mi.file) { seen = true; };
                        k++;
                    };
                    if (!seen) { ffree(mi.file); };
                };
                pv_free(mi.deps);
                pv_free(mi.locked);
                pv_free(mi.using_ns);
                pv_free(mi.platform);
                pv_free(mi.requires);
                ffree((byte*)mi);
                i++;
            };
            i = 0;
            while (i < u.files.count)
            {
                pv_free((PtrVec*)u.files.vals[i]);
                i++;
            };
            i = 0;
            while (i < u.warnings.len)
            {
                ffree((byte*)u.warnings.items[i]);
                i++;
            };
            if (u.err != (byte*)0) { ffree(u.err); };
            pv_free(u.mods);
            pv_free(u.order);
            pv_free(u.programs);
            pv_free(u.warnings);
            nm_free(u.files);
            nm_free(u.unbuilt);
            ffree((byte*)u);
            ->;
        };

        // Maps every function of the modules to its module. Must run on the flattened
        // program before DCE: each module body is collected with the call graph's own
        // naming, so the names match what the checkers see.
        mu_func_map(ModUnit* u) -> ModMap*
        {
            ModMap* mm = (ModMap*)fmalloc((u64)((sizeof(ModMap) + 7) / 8));
            ModInfo* mi;
            Node* tmp;
            int i, j;
            byte* bare;
            mm.own = (BcOwners*)fmalloc((u64)((sizeof(BcOwners) + 7) / 8));
            mm.own.full = nm_new();
            mm.own.bare = nm_new();
            mm
            {
                .on_borrow = nm_new();
                .on_effect = nm_new();
            };
            CallGraph cg;
            while (i < u.order.len)
            {
                mi = (ModInfo*)u.order.items[i];
                i++;
                if (mi.borrow_check) { nm_put(mm.on_borrow, mi.name, (void*)1); };
                if (mi.effect_check) { nm_put(mm.on_effect, mi.name, (void*)1); };
                tmp = node_new(NodeKind.PROGRAM, 1, 1);
                j = 0;
                while (j < node_count(mi.node, 0))
                {
                    node_push(tmp, 0, node_child(mi.node, 0, j));
                    j++;
                };
                cg.__init();
                cg.collect(tmp);
                j = 0;
                while (j < cg.funcs.count)
                {
                    nm_put(mm.own.full, (byte*)cg.funcs.keys[j], (void*)mi.name);
                    bare = bc_last_seg((byte*)cg.funcs.keys[j]);
                    if (!nm_has(mm.own.bare, bare)) { nm_put(mm.own.bare, bare, (void*)mi.name); };
                    ffree(bare);
                    j++;
                };
                cg.__exit();
                // the module's statements belong to the module, so only the list is released
                tmp.l0.len = 0;
                node_free(tmp);
            };
            -> mm;
        };

        mm_free(ModMap* mm) -> void
        {
            if (mm == (ModMap*)0) { ->; };
            nm_free(mm.own.full);
            nm_free(mm.own.bare);
            ffree((byte*)mm.own);
            nm_free(mm.on_borrow);
            nm_free(mm.on_effect);
            ffree((byte*)mm);
            ->;
        };

        // Names of the modules that still own a function in prog (the pruned program)
        mu_live_modules(ModMap* mm, Node* prog) -> NameMap*
        {
            NameMap* live = nm_new();
            CallGraph cg;
            int j;
            byte* owner;
            cg.__init();
            cg.collect(prog);
            while (j < cg.funcs.count)
            {
                owner = bc_owner_of(mm.own, (byte*)cg.funcs.keys[j]);
                if (owner != (byte*)0) { nm_put(live, owner, (void*)1); };
                j++;
            };
            cg.__exit();
            -> live;
        };

        // Mangled names of every function of a module that sets dce = false
        mu_dce_roots(ModUnit* u, ModMap* mm) -> PtrVec*
        {
            PtrVec* r = pv_new();
            int i;
            ModInfo* mi;
            while (i < mm.own.full.count)
            {
                mi = mu_find(u, (byte*)mm.own.full.vals[i]);
                if (mi != (ModInfo*)0)
                {
                    if (!mi.dce) { pv_push(r, mm.own.full.keys[i]); };
                };
                i++;
            };
            -> r;
        };
    };
};

#endif;
