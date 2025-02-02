const std = @import("std");
const sdl = @cImport({
    @cInclude("SDL2/SDL.h");
});
const assert = std.debug.assert;
const expect = std.testing.expect;

// 2D vector to rerpesent the tetris board
const InvisibleRows = 3;
const InvisibleCols = 3;
const BoardWidth = 8 + 2 * InvisibleCols;
const BoardHeight = 12 + 2 * InvisibleRows;
const BoardSize = BoardWidth * BoardHeight;
const BoardType = [BoardHeight][BoardWidth]u8;

// Color struct
const Color = struct {
    r: u8,
    g: u8,
    b: u8,
};

const ColorWhite = Color{ .r = 255, .g = 255, .b = 255 };
const ColorBlack = Color{ .r = 0, .g = 0, .b = 0 };
const ColorPurple = Color{ .r = 128, .g = 0, .b = 128 };
const ColorPink = Color{ .r = 255, .g = 192, .b = 203 };
const ColorSalmon = Color{ .r = 250, .g = 128, .b = 114 };
const ColorLime = Color{ .r = 191, .g = 255, .b = 0 };
const ColorTeal = Color{ .r = 0, .g = 128, .b = 128 };
const ColorCoral = Color{ .r = 255, .g = 127, .b = 80 };
const ColorOlive = Color{ .r = 128, .g = 128, .b = 255 };
const ColorRed = Color{ .r = 255, .g = 0, .b = 0 };

// Convert u8 to Color
fn toColor(val: u8) Color {
    switch (val) {
        1 => return ColorPurple,
        2 => return ColorPink,
        3 => return ColorSalmon,
        4 => return ColorLime,
        5 => return ColorTeal,
        6 => return ColorCoral,
        7 => return ColorOlive,
        8 => return ColorRed,
        else => return ColorBlack,
    }
}

fn colorToInt(color: Color) u8 {
    if (std.meta.eql(color, ColorPurple)) {
        return 1;
    } else if (std.meta.eql(color, ColorPink)) {
        return 2;
    } else if (std.meta.eql(color, ColorSalmon)) {
        return 3;
    } else if (std.meta.eql(color, ColorLime)) {
        return 4;
    } else if (std.meta.eql(color, ColorTeal)) {
        return 5;
    } else if (std.meta.eql(color, ColorCoral)) {
        return 6;
    } else if (std.meta.eql(color, ColorOlive)) {
        return 7;
    } else if (std.meta.eql(color, ColorRed)) {
        return 8;
    } else {
        return 0;
    }
}

const TetrominoType = enum {
    I,
    J,
    L,
    O,
    S,
    T,
    Z,
};

fn toString(tetrominoType: TetrominoType) []const u8 {
    switch (tetrominoType) {
        TetrominoType.I => return "I",
        TetrominoType.J => return "J",
        TetrominoType.L => return "L",
        TetrominoType.O => return "O",
        TetrominoType.S => return "S",
        TetrominoType.T => return "T",
        TetrominoType.Z => return "Z",
    }
}

// Tetris piece, aka tetromino
const Tetromino = struct {
    size: u8,
    blocks: [4]u16,
    color: Color,
    type: TetrominoType,
};

const TetrominoI = Tetromino{ .size = 4, .blocks = .{ 0x0F00, 0x2222, 0x00F0, 0x4444 }, .color = ColorPurple, .type = TetrominoType.I };
const TetrominoJ = Tetromino{ .size = 3, .blocks = .{ 0x44C0, 0x8E00, 0x6440, 0x0E20 }, .color = ColorPink, .type = TetrominoType.J };
const TetrominoL = Tetromino{ .size = 3, .blocks = .{ 0x4460, 0x0E80, 0xC440, 0x2E00 }, .color = ColorSalmon, .type = TetrominoType.L };
const TetrominoO = Tetromino{ .size = 2, .blocks = .{ 0xCC00, 0xCC00, 0xCC00, 0xCC00 }, .color = ColorLime, .type = TetrominoType.O };
const TetrominoS = Tetromino{ .size = 3, .blocks = .{ 0x06C0, 0x8C40, 0x6C00, 0x4620 }, .color = ColorTeal, .type = TetrominoType.S };
const TetrominoT = Tetromino{ .size = 3, .blocks = .{ 0x0E40, 0x4C40, 0x4E00, 0x4640 }, .color = ColorCoral, .type = TetrominoType.T };
const TetrominoZ = Tetromino{ .size = 3, .blocks = .{ 0x0C60, 0x4C80, 0xC600, 0x2640 }, .color = ColorOlive, .type = TetrominoType.Z };

fn generateRandomTetromino() !Tetromino {
    var prng = std.rand.DefaultPrng.init(blk: {
        var seed: u64 = undefined;
        try std.posix.getrandom(std.mem.asBytes(&seed));
        break :blk seed;
    });
    const rand = prng.random();
    const tetrominos = [_]Tetromino{ TetrominoI, TetrominoJ, TetrominoL, TetrominoO, TetrominoS, TetrominoT, TetrominoZ };
    const randIndex = rand.intRangeAtMost(usize, 0, tetrominos.len - 1);
    const tetromino = tetrominos[randIndex];
    std.log.info("New tetromino: {s}\n", .{toString(tetromino.type)});
    return tetromino;
}

const TetrominoPosition = struct {
    x: usize,
    y: usize,
};

fn getDefaultTetrominoPosition() TetrominoPosition {
    return TetrominoPosition{ .x = BoardWidth / 2, .y = InvisibleRows };
}

fn isBitSetAtIndex(value: u16, index: usize) bool {
    assert(index < 16);
    const MaskInt = std.meta.Int(.unsigned, 16);
    const ShiftInt = std.math.Log2Int(MaskInt);
    const maskBit = @as(MaskInt, 1) << @as(ShiftInt, @intCast(index));
    return (value & maskBit) != 0;
}

fn isCellInvisible(row: usize, col: usize) bool {
    return row < InvisibleRows or row >= BoardHeight - InvisibleRows or col < InvisibleCols or col >= BoardWidth - InvisibleCols;
}

// For now, I'll just translate the u16 blocks to 4 [4]u8 blocks to make it easier to draw
// the tetromino on the board. Each block will be written to the board directly as an 32-bit integer.
// Orientation determines which block to use.
// The values of the blocks will be the color of the tetromino as calculated via `colorToInt` (e.g., TetrominoI will print 1).
fn drawTetromino(board: *BoardType, tetromino: Tetromino, position: TetrominoPosition, orientation: usize, color: u8) void {
    const x = position.x;
    const y = position.y;
    const blocks = tetromino.blocks[orientation];
    const size: usize = 4;
    var row_index: usize = 0;
    while (row_index < size) {
        var col_index: usize = 0;
        while (col_index < size) {
            const board_row = y + row_index;
            const board_col = x + col_index;
            if (isCellInvisible(board_row, board_col)) {
                col_index += 1;
                continue;
            }
            const bit = isBitSetAtIndex(blocks, row_index * size + col_index);
            if (bit) {
                board[board_row][board_col] = color;
            } else {
                // for debug purposes
                if (color == 0) {
                    board[board_row][board_col] = color;
                } else {
                    board[board_row][board_col] = colorToInt(ColorRed);
                }
            }
            col_index += 1;
        }
        row_index += 1;
    }
}

// Determine if the tetromino can be placed on the board
fn canPlaceTetromino(board: *BoardType, tetromino: Tetromino, position: TetrominoPosition, orientation: usize) bool {
    const x = position.x;
    const y = position.y;
    const blocks = tetromino.blocks[orientation];
    const size: usize = 4;
    var row_index: usize = 0;
    while (row_index < size) {
        var col_index: usize = 0;
        while (col_index < size) {
            const bit = isBitSetAtIndex(blocks, row_index * size + col_index);
            if (bit) {
                const board_row = y + row_index;
                const board_col = x + col_index;
                if (board[board_row][board_col] != 0) {
                    return false;
                }
            }
            col_index += 1;
        }
        row_index += 1;
    }
    return true;
}

// Handle input
fn handleInput(keys: *std.AutoHashMap(i32, bool), board: *BoardType, pos: *TetrominoPosition, orientation: *usize, tetromino: Tetromino) !void {
    if (keys.get(sdl.SDLK_LEFT) orelse false) {
        var new_x = pos.x;
        var new_pos = pos.*;
        if (pos.x > 0) {
            new_x -= 1;
            new_pos.x = new_x;
        }
        drawTetromino(board, tetromino, pos.*, orientation.*, colorToInt(ColorBlack));
        std.log.info("Left key pressed. Position change from x={} to x={}\n", .{ pos.x, new_x });
        if (canPlaceTetromino(board, tetromino, new_pos, orientation.*)) {
            pos.x = new_x;
        }
        // drawTetromino(board, tetromino, pos.*, orientation.*, colorToInt(ColorBlack));
        // std.log.info("Left key pressed. Position change from x={} to x={}\n", .{ pos.x, new_x });
        // pos.x = new_x;
        try keys.put(sdl.SDLK_LEFT, false);
    }
    if (keys.get(sdl.SDLK_RIGHT) orelse false) {
        var new_x = pos.x;
        if (pos.x + 4 < BoardWidth - 2) {
            new_x += 1;
        }
        drawTetromino(board, tetromino, pos.*, orientation.*, colorToInt(ColorBlack));
        std.log.info("Right key pressed. Position change from x={} to x={}\n", .{ pos.x, new_x });
        pos.x = new_x;
        try keys.put(sdl.SDLK_RIGHT, false);
    }
    if (keys.get(sdl.SDLK_DOWN) orelse false) {
        std.log.info("Down\n", .{});
    }
    if (keys.get(sdl.SDLK_UP) orelse false) {
        const old_orientation = orientation.*;
        drawTetromino(board, tetromino, pos.*, orientation.*, colorToInt(ColorBlack));
        orientation.* = (orientation.* + 1) % 4;
        std.log.info("Up key pressed. Orientation change from x={} to x={}\n", .{ old_orientation, orientation.* });
        try keys.put(sdl.SDLK_UP, false);
    }
}

pub fn main() !void {
    if (sdl.SDL_Init(sdl.SDL_INIT_VIDEO | sdl.SDL_INIT_TIMER) != 0) {
        std.log.err("SDL_Init Error: {*}\n", .{sdl.SDL_GetError()});
        return;
    }

    const window = sdl.SDL_CreateWindow(
        "Zig Tetris",
        sdl.SDL_WINDOWPOS_CENTERED,
        sdl.SDL_WINDOWPOS_CENTERED,
        800,
        600,
        sdl.SDL_WINDOW_SHOWN,
    );
    if (window == null) {
        std.log.err("SDL_CreateWindow Error: {*}\n", .{sdl.SDL_GetError()});
        sdl.SDL_Quit();
        return;
    }

    const renderer = sdl.SDL_CreateRenderer(window, -1, sdl.SDL_RENDERER_ACCELERATED | sdl.SDL_RENDERER_PRESENTVSYNC);
    if (renderer == null) {
        std.log.err("SDL_CreateRenderer Error: {*}\n", .{sdl.SDL_GetError()});
        sdl.SDL_DestroyWindow(window);
        sdl.SDL_Quit();
        return;
    }

    // Initialize tetris board
    var board: BoardType = .{.{0} ** BoardWidth} ** BoardHeight;

    // Allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    // Keyboard states in a map
    // true if key is pressed, false otherwise
    var keys = std.AutoHashMap(i32, bool).init(allocator);
    defer keys.deinit();

    // Main loop
    var generateNewTetromino = true;
    var tetrominoOrientation: usize = 0;
    var tetromino = try generateRandomTetromino();
    var quit = false;
    var tetrominoPosition = getDefaultTetrominoPosition();
    var event: sdl.SDL_Event = undefined;
    while (!quit) {
        while (sdl.SDL_PollEvent(&event) != 0) {
            switch (event.type) {
                sdl.SDL_KEYDOWN => {
                    try keys.put(event.key.keysym.sym, true);
                },
                sdl.SDL_KEYUP => {
                    try keys.put(event.key.keysym.sym, false);
                },
                sdl.SDL_QUIT => {
                    quit = true;
                },
                else => {},
            }
        }

        _ = sdl.SDL_SetRenderDrawColor(renderer, ColorBlack.r, ColorBlack.g, ColorBlack.b, 255);
        _ = sdl.SDL_RenderClear(renderer);

        // Tetris board frame color
        const boardColor = ColorWhite;

        if (generateNewTetromino) {
            tetromino = try generateRandomTetromino();
            generateNewTetromino = false;
            tetrominoPosition = getDefaultTetrominoPosition();
        }

        drawTetromino(&board, tetromino, tetrominoPosition, tetrominoOrientation, colorToInt(tetromino.color));
        // Fill all the invisible cells with non-zero values to prevent tetromino from moving outside the board
        // the invisible cells are the first 3 rows and columns and the last 3 rows and columns
        for (board, 0..) |row, row_index| {
            for (row, 0..) |_, cell_index| {
                if (row_index < InvisibleRows or row_index >= BoardHeight - InvisibleRows or cell_index < InvisibleCols or cell_index >= BoardWidth - InvisibleCols) {
                    board[row_index][cell_index] = 8;
                }
            }
        }

        // Draw tetris board
        // Todo replace with these to avoid rendering invisible cells
        // for (board[InvisibleRows .. board.len - InvisibleRows], InvisibleRows..) |row, row_index| {
        //     for (row[InvisibleCols .. row.len - InvisibleCols], InvisibleCols..) |cell, cell_index| {
        for (board, 0..) |row, row_index| {
            for (row, 0..) |cell, cell_index| {
                const cell_idx_c_int: i32 = @intCast(cell_index);
                const row_idx_c_int: i32 = @intCast(row_index);
                const rect = sdl.SDL_Rect{ .x = cell_idx_c_int * 20, .y = row_idx_c_int * 20, .w = 20, .h = 20 };
                const color = toColor(cell);
                _ = sdl.SDL_SetRenderDrawColor(renderer, color.r, color.g, color.b, 255);
                _ = sdl.SDL_RenderFillRect(renderer, &rect);
                _ = sdl.SDL_SetRenderDrawColor(renderer, boardColor.r, boardColor.g, boardColor.b, 255);
                _ = sdl.SDL_RenderDrawRect(renderer, &rect);
            }
        }

        // Update board based on input
        try handleInput(&keys, &board, &tetrominoPosition, &tetrominoOrientation, tetromino);

        sdl.SDL_RenderPresent(renderer);
    }

    sdl.SDL_DestroyRenderer(renderer);
    sdl.SDL_DestroyWindow(window);
    sdl.SDL_Quit();
}

test "isBitSetAtIndex" {
    const value: u16 = 0x0F00;
    try expect(isBitSetAtIndex(value, 0) == false);
    try expect(isBitSetAtIndex(value, 8) == true);
}

test "isCellInvisible" {
    try expect(isCellInvisible(0, 0) == true);
    try expect(isCellInvisible(InvisibleRows, InvisibleCols) == false);
    try expect(isCellInvisible(BoardHeight - 1, BoardWidth - 1) == true);
}
