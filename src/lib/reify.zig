const std = @import("std");

pub fn Type(comptime info: std.builtin.Type) type {
    return switch (info) {
        .@"struct" => |s| Struct(s),
        .@"enum" => |e| Enum(e),
        .@"union" => |u| Union(u),
        .@"fn" => |f| Fn(f),
        else => @compileError("unsupported type info: " ++ @tagName(info)),
    };
}

pub fn Struct(comptime info: std.builtin.Type.Struct) type {
    comptime var field_names: [info.fields.len][]const u8 = undefined;
    comptime var field_types: [info.fields.len]type = undefined;
    comptime var field_attrs: [info.fields.len]std.builtin.Type.StructField.Attributes = undefined;

    for (info.fields, 0..) |field, i| {
        field_names[i] = field.name;
        field_types[i] = field.type;
        field_attrs[i] = .{
            .default_value_ptr = field.default_value_ptr,
            .@"comptime" = field.is_comptime,
            .@"align" = if (info.layout == .@"packed") null else field.alignment,
        };
    }

    return @Struct(info.layout, info.backing_integer, &field_names, &field_types, &field_attrs);
}

pub fn Enum(comptime info: std.builtin.Type.Enum) type {
    comptime var field_names: [info.fields.len][]const u8 = undefined;
    comptime var field_values: [info.fields.len]info.tag_type = undefined;

    for (info.fields, 0..) |field, i| {
        field_names[i] = field.name;
        field_values[i] = @intCast(field.value);
    }

    return @Enum(
        info.tag_type,
        if (info.is_exhaustive) .exhaustive else .nonexhaustive,
        &field_names,
        &field_values,
    );
}

pub fn Union(comptime info: std.builtin.Type.Union) type {
    comptime var field_names: [info.fields.len][]const u8 = undefined;
    comptime var field_types: [info.fields.len]type = undefined;
    comptime var field_attrs: [info.fields.len]std.builtin.Type.UnionField.Attributes = undefined;

    for (info.fields, 0..) |field, i| {
        field_names[i] = field.name;
        field_types[i] = field.type;
        field_attrs[i] = .{ .@"align" = field.alignment };
    }

    return @Union(info.layout, info.tag_type, &field_names, &field_types, &field_attrs);
}

pub fn Fn(comptime info: std.builtin.Type.Fn) type {
    if (info.is_generic) @compileError("generic function reification is unsupported");
    const return_type = info.return_type orelse @compileError("function return type is required");

    comptime var param_types: [info.params.len]type = undefined;
    comptime var param_attrs: [info.params.len]std.builtin.Type.Fn.Param.Attributes = undefined;

    for (info.params, 0..) |param, i| {
        param_types[i] = param.type orelse @compileError("generic parameter reification is unsupported");
        param_attrs[i] = .{ .@"noalias" = param.is_noalias };
    }

    return @Fn(
        &param_types,
        &param_attrs,
        return_type,
        .{
            .@"callconv" = info.calling_convention,
            .varargs = info.is_var_args,
        },
    );
}
