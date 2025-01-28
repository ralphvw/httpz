const std = @import("std");
const pg = @import("pg");
const httpz = @import("httpz");
const rediz = @import("rediz");

const Ctx = struct { db: *pg.Pool, redis: rediz.RedisClient };
const User = struct { first_name: []const u8, last_name: []const u8, email: []const u8 };

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const uri = try std.Uri.parse("postgresql://postgres:admin@localhost:5432/zig_db");
    const pool = try pg.Pool.initUri(allocator, uri, 5, 10_000);
    defer pool.deinit();
    var redisClient = try rediz.RedisClient.connect(allocator, "redis://127.0.0.1:6379");
    defer redisClient.disconnect();

    var ctx = Ctx{ .db = pool, .redis = redisClient };
    const port = 5882;

    var server = try httpz.ServerApp(*Ctx).init(allocator, .{ .port = port }, &ctx);

    server.notFound(notFound);

    server.errorHandler(errorHandler);

    var router = server.router();

    router.get("/api/user/:id", getUser);
    router.post("/api/user", insertUser);

    std.debug.print("Attempting to listen", .{});
    try server.listen();
    std.debug.print("Server listening on port: {d}\n", .{port});
}

fn getUser(ctx: *Ctx, _: *httpz.Request, res: *httpz.Response) !void {
    const redisRes = try ctx.redis.get("somestation");

    try res.json(.{ .data = redisRes orelse "" }, .{});
}

fn insertUser(ctx: *Ctx, req: *httpz.Request, res: *httpz.Response) !void {
    const user = try req.json(User);
    if (user == null) {
        res.status = 400;
        res.body = "Invalid request body";
        return;
    }

    var result = try ctx.db.query("INSERT INTO users (first_name, last_name, email) VALUES ($1, $2, $3) RETURNING id, first_name, last_name, email", .{ user.?.first_name, user.?.last_name, user.?.email });
    defer result.deinit();

    _ = try res.json(.{.user}, .{});
}

fn notFound(_: *Ctx, _: *httpz.Request, res: *httpz.Response) !void {
    res.status = 404;
    res.body = "Not Found";
}

fn errorHandler(_: *Ctx, req: *httpz.Request, res: *httpz.Response, err: anyerror) void {
    res.status = 500;
    res.body = "Internal Server Error";
    std.log.warn("httpz: unhandled exception for request: {s}\nErr: {}", .{ req.url.raw, err });
}
