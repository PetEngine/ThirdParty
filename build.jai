Build :: enum_flags u64 {
    shaderc;
    spirv_reflect;
    jaison;
}

#run {
    set_build_options_dc(.{ do_output = false });

    build := parseCommandLine();
    if !build return;

    wd := get_working_directory();
    if !wd {
        fatal("get_working_directory() has failed");
    }
    defer set_working_directory(wd);

    if !set_working_directory(#filepath) {
        fatal("set_working_directory(\"%\") has failed", #filepath);
    }

    if !make_directory_if_it_does_not_exist("output") {
        fatal("make_directory_if_it_does_not_exist(\"output\") has failed");
    }

    if build & .shaderc {
        auto_release_temp();
        if !buildShaderc()    then fatal("shaderc build has failed");
        if !generateShaderc() then fatal("shaderc generation has failed");
    }

    if build & .spirv_reflect {
        auto_release_temp();
        if !buildSpirvReflect()    then fatal("SPIRV-Reflect build has failed");
        if !generateSpirvReflect() then fatal("SPIRV-Reflect generation has failed");
    }

    if build & .jaison {
        if !generateJaison() then fatal("jaison generation has failed");
    }
}

//
// shaderc
//

buildShaderc :: () -> bool #compile_time {
    write_string("\n>>> shaderc build has started\n");

    if !file_exists("shaderc/build") {
        result := run_command("python", "shaderc/utils/git-sync-deps");
        if result.type != .EXITED || result.exit_code != 0 {
            error("\"python ./utils/git-sync-deps\" has failed: %", result);
            return false;
        }

        if !make_directory_if_it_does_not_exist("shaderc/build") {
            error("make_directory_if_it_does_not_exist(\"shaderc/build\") has failed\n");
            return false;
        }

        result = run_command("cmake", "-S", "shaderc", "-B", "shaderc/build");
        if result.type != .EXITED || result.exit_code != 0 {
            error("cmake generation has failed: %", result);
            return false;
        }
    }

    result := run_command("cmake", "--build", "shaderc/build", "--config", "RelWithDebInfo", "--parallel");
    if result.type != .EXITED || result.exit_code != 0 {
        error("cmake build has failed: %", result);
        return false;
    }

    write_string(">>> shaderc build has ended\n");
    return true;
}

generateShaderc :: () -> bool #compile_time {
    write_string("\n>>> shaderc generation has started\n");

    delete_directory("output/shaderc");
    if !make_directory_if_it_does_not_exist("output/shaderc/bin", true) {
        error("make_directory_if_it_does_not_exist(\"output/shaderc/bin\") has failed\n");
        return false;
    }

    if !copy_file("shaderc/build/libshaderc/RelWithDebInfo/shaderc_shared.dll", "output/shaderc/bin/shaderc_shared.dll") {
        error("copy_file(shaderc_shared.dll) has failed");
        return false;
    }
    if !copy_file("shaderc/build/libshaderc/RelWithDebInfo/shaderc_shared.lib", "output/shaderc/bin/shaderc_shared.lib") {
        error("copy_file(shaderc_shared.lib) has failed");
        return false;
    }
    if !copy_file("shaderc/LICENSE", "output/shaderc/LICENSE") {
        error("copy_file(LICENSE) has failed");
        return false;
    }

    options : Generate_Bindings_Options;
    options.alias_original_enum_names = false;

    array_add(*options.library_search_paths, "shaderc/build/libshaderc/RelWithDebInfo");
    array_add(*options.libraries,            .{ "shaderc_shared", "shaderc" });

    array_add(*options.include_paths, "shaderc/libshaderc/include");
    array_add(*options.source_files,  "shaderc/shaderc.h");

    // array_add(*options.strip_prefixes, "shaderc");

    result_builder, success := generate_bindings(options, true);
    if !success {
        error("generate_bindings has failed\n");
        return false;
    }

    result := builder_to_string(*result_builder,, allocator = temp);
    result  = replace(result, "shaderc/build/libshaderc/RelWithDebInfo", "bin",, allocator = temp);

    if !write_entire_file("output/shaderc/module.jai", result) {
        error("write_entire_file has failed");
        return false;
    }

    write_string(">>> shaderc generation has ended\n");
    return true;
}

//
// SPIRV-Reflect
//

buildSpirvReflect :: () -> bool #compile_time {
    write_string("\n>>> SPIRV-Reflect build has started\n");

    if !file_exists("spirv_reflect/build") {
        if !make_directory_if_it_does_not_exist("spirv_reflect/build") {
            error("make_directory_if_it_does_not_exist(\"spirv_reflect/build\") has failed\n");
            return false;
        }

        result := run_command("cmake", "-S", "spirv_reflect", "-B", "spirv_reflect/build", "-D", "SPIRV_REFLECT_EXECUTABLE=OFF", "-D", "SPIRV_REFLECT_STATIC_LIB=ON", "-D", "SPIRV_REFLECT_INSTALL=OFF");
        if result.type != .EXITED || result.exit_code != 0 {
            error("cmake generation has failed: %", result);
            return false;
        }
    }

    result := run_command("cmake", "--build", "spirv_reflect/build", "--config", "RelWithDebInfo", "--parallel");
    if result.type != .EXITED || result.exit_code != 0 {
        error("cmake build has failed: %", result);
        return false;
    }

    write_string(">>> SPIRV-Reflect build has ended\n");
    return true;
}

generateSpirvReflect :: () -> bool #compile_time {
    write_string("\n>>> SPIRV-Reflect generation has started\n");

    delete_directory("output/spirv_reflect");
    if !make_directory_if_it_does_not_exist("output/spirv_reflect/bin", true) {
        error("make_directory_if_it_does_not_exist(\"output/spirv_reflect/bin\") has failed\n");
        return false;
    }

    if !copy_file("spirv_reflect/build/RelWithDebInfo/spirv-reflect-static.lib", "output/spirv_reflect/bin/spirv-reflect-static.lib") {
        error("copy_file(spirv-reflect-static.lib) has failed");
        return false;
    }
    if !copy_file("spirv_reflect/build/RelWithDebInfo/spirv-reflect-static.pdb", "output/spirv_reflect/bin/spirv-reflect-static.pdb") {
        error("copy_file(spirv-reflect-static.pdb) has failed");
        return false;
    }
    if !copy_file("spirv_reflect/LICENSE", "output/spirv_reflect/LICENSE") {
        error("copy_file(LICENSE) has failed");
        return false;
    }

    options : Generate_Bindings_Options;
    options.alias_original_enum_names = false;
    options.visitor = spirvReflectVisitor;

    array_add(*options.library_search_paths, "spirv_reflect/build/RelWithDebInfo");
    array_add(*options.libraries,            .{ "spirv-reflect-static", "spirv_reflect" });

    array_add(*options.include_paths, "spirv_reflect");
    array_add(*options.source_files,  "spirv_reflect.h");

    result_builder, success := generate_bindings(options, true);
    defer deinit(*g_spirv_reflect_enum_flags);
    if !success {
        error("generate_bindings has failed\n");
        return false;
    }

    result := builder_to_string(*result_builder,, allocator = temp);
    result  = replace(result, "spirv_reflect/build/RelWithDebInfo", "bin",, allocator = temp);

    if !write_entire_file("output/spirv_reflect/module.jai", result) {
        error("write_entire_file has failed");
        return false;
    }

    write_string(">>> SPIRV-Reflect generation has ended\n");
    return true;
}

g_spirv_reflect_enum_flags : Table(string, *Enum);
spirvReflectVisitor :: (decl: *Declaration, parent_decl: *Declaration) -> Declaration_Visit_Result #compile_time {
    if decl.kind == {
        case .ENUM;
            enum_decl := cast(*Enum) decl;
            if ends_with(enum_decl.name, "FlagBits") {
                enum_decl.flags |= .IS_ENUM_FLAGS;
                enum_decl.flags |= .VALUES_IN_HEX;
                table_add(*g_spirv_reflect_enum_flags, enum_decl.name, enum_decl);
            }

        case .TYPEDEF;
            if ends_with(decl.name, "Flags") {
                flag_bits_name := replace(decl.name, "Flags", "FlagBits",, allocator = temp);

                found, enum_decl := table_find(*g_spirv_reflect_enum_flags, flag_bits_name);
                if found {
                    assert(enum_decl != null);

                    decl.type = New(CType);
                    decl.type.type_of_enum = enum_decl;
                    decl.type.size         = enum_decl.type.size;
                }
            }
    }

    return .RECURSE;
}

//
// jaison
//

generateJaison :: () -> bool #compile_time {
    write_string("\n>>> jaison generation has started\n");

    delete_directory("output/jaison");
    if !make_directory_if_it_does_not_exist("output/jaison/unicode_utils", true) {
        error("make_directory_if_it_does_not_exist(\"output/jaison/unicode_utils\") has failed\n");
        return false;
    }

    if !copy_file("jaison/module.jai", "output/jaison/module.jai") {
        error("copy_file(module.jai) has failed");
        return false;
    }
    if !copy_file("jaison/generic.jai", "output/jaison/generic.jai") {
        error("copy_file(generic.jai) has failed");
        return false;
    }
    if !copy_file("jaison/typed.jai", "output/jaison/typed.jai") {
        error("copy_file(typed.jai) has failed");
        return false;
    }
    if !copy_file("jaison/LICENSE", "output/jaison/LICENSE") {
        error("copy_file(LICENSE) has failed");
        return false;
    }
    if !copy_file("jaison/unicode_utils/module.jai", "output/jaison/unicode_utils/module.jai") {
        error("copy_file(unicode_utils/module.jai) has failed");
        return false;
    }

    write_string(">>> jaison generation has ended\n");
    return true;
}

//
// Utils
//

parseCommandLine :: () -> Build #compile_time {
    INFO :: type_info(Build);
    #assert INFO.type == .ENUM;

    build_options := get_build_options();

    if !build_options.compile_time_command_line {
        write_string("Specify the name of third-party to build");
        return 0;
    }

    build : Build;

    for command_line_argument : build_options.compile_time_command_line {
        if command_line_argument == "all" {
            for INFO.values { build |= cast(Build) it; }
            break;
        }

        for INFO.names {
            if it == command_line_argument {
                build |= cast(Build) INFO.values[it_index];
                continue command_line_argument;
            }
        }

        fatal("Unrecognized command line argument: \"%\"", command_line_argument);
    }

    return build;
}

error :: (format : string, args : ..Any, location := #caller_location) #compile_time {
    message := tprint(format, ..args);
    compiler_report(message, location, .ERROR_CONTINUABLE);
}

fatal :: (format : string, args : ..Any, location := #caller_location) #compile_time {
    message := tprint(format, ..args);
    compiler_report(message, location, .ERROR);
}

#import "Basic";
#import "Bindings_Generator";
#import "Compiler";
#import "File";
#import "File_Utilities";
#import "Hash_Table";
#import "Process";
#import "String";
