const std = @import("std");
const sdl = @cImport({
    @cInclude("SDL2/SDL.h");
    @cInclude("SDL2/SDL_ttf.h");
});
const assert = std.debug.assert;
const expect = std.testing.expect;

// Design
// The board is a 2D array of cells responsible for the game state.
// The board helps to determine the next state of the game, e.g. whether a piece can move or not.
// The board thus is a bitmap that can be directly written to.
// Tetrominoes are the game pieces that move around the board. They are defined by their shape, position, and rotation.
// Tetrominoes can be active (moving) or inactive (landed). The main loops handles key presses to move and rotate the active piece.
// The main loop also keeps track of the game state, e.g. whether the game is over or not.

// Tetrominoes
// Tetrominoes are defined by their shape, position, and rotation.
// Each tetromino has a bounding box of 4x4 cells.
// Tetrominoes of each type have a present values for each of the 4 rotations.
// The values store the color and can be directly written to the board.
// This requires much more memory than neccessary for representation but simplifies the code.
// Tetrominoes are referenced by a single-letter code (I, J, L, O, S, T, Z).

// The board
// The board is a 2D grid of cells. Each cell can be empty or filled.
// Filled cells are colored according to the tetromino that occupies them.
// The board has a fixed size. There are sentinel rows at the top and bottom, as well as left and right, to simplify collision detection.
// Those sentinel rows and cols are always filled and are not rendred (they are in the debug version and have a different color).

// The game loop
// The game loop is responsible for handling user input, updating the game state, and rendering the game.

// The game state
// The game state keeps track of the current score, level, and lines cleared.
// The game state also keeps track of the current tetromino and the next tetromino.
// The game can be in one of three states: playing, paused, or game over.

const DebugMode = false;

const GameStateEnum = enum {
    playing,
    paused,
    game_over,
    quit,
};

const GameState = struct {
    score: u32 = 0,
    level: u32 = 0,
    lines: u32 = 0,
    state: GameStateEnum = .playing,

    current_tetromino: Tetromino = undefined,
    next_tetromino: Tetromino = undefined,

    // This stores user input for smooth processing.
    keys: std.AutoHashMap(i32, bool) = undefined,
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};

    pub fn init(self: *GameState) void {
        self.current_tetromino = generateTetromino(self);
        self.next_tetromino = generateTetromino(self);

        const allocator = gpa.allocator();
        self.keys = std.AutoHashMap(i32, bool).init(allocator);
    }

    pub fn pause(self: *GameState) void {
        self.state = GameStateEnum.paused;
    }

    pub fn unpause(self: *GameState) void {
        self.state = GameStateEnum.playing;
    }

    pub fn gameover(self: *GameState) void {
        self.state = GameStateEnum.game_over;
    }

    pub fn quit(self: *GameState) void {
        self.state = GameStateEnum.quit;
    }

    pub fn updateScore(self: *GameState, lines_cleared: u32) void {
        if (lines_cleared == 0) return;
        self.lines += lines_cleared;
        self.score += lines_cleared * 100;
        if (self.lines % 5 == 0 and self.lines != 0 and self.level < 20) {
            // if (self.lines != 0 and self.level < 20) {
            self.level += 1;
        }
    }

    fn generateTetromino(self: *GameState) Tetromino {
        const rand = std.crypto.random;
        const types = [_]TetrominoType{ TetrominoType.I, TetrominoType.J, TetrominoType.L, TetrominoType.O, TetrominoType.S, TetrominoType.T, TetrominoType.Z };
        // const types = [_]TetrominoType{TetrominoType.I};
        const randIndex = rand.intRangeAtMost(usize, 0, types.len - 1);
        const ttype = types[randIndex];
        const pos = getDefaultTetrominoPosition(self);
        const shape = getShape(ttype);
        const color = getColor(ttype);
        const shapes = .{ generateColoredTetrominoBufferFromShape(shape[0], color), generateColoredTetrominoBufferFromShape(shape[1], color), generateColoredTetrominoBufferFromShape(shape[2], color), generateColoredTetrominoBufferFromShape(shape[3], color) };
        return Tetromino{ .type = ttype, .shape = shapes, .pos = pos };
    }

    fn getDefaultTetrominoPosition(_: *GameState) Position {
        // todo: move x to the invisible cols
        return Position{ .x = InvisibleCols, .y = BoardWidth / 2 - 2 };
    }
};

const Color = enum {
    empty,
    cyan,
    blue,
    orange,
    yellow,
    green,
    purple,
    pink,
    red,
    white,
    dark_blue,
};

const RGB = struct {
    r: u8,
    g: u8,
    b: u8,
};

fn getRGB(color: Color) RGB {
    switch (color) {
        Color.empty => return .{ .r = 0, .g = 0, .b = 0 },
        Color.cyan => return .{ .r = 0, .g = 255, .b = 255 },
        Color.blue => return .{ .r = 0, .g = 0, .b = 255 },
        Color.orange => return .{ .r = 255, .g = 165, .b = 0 },
        Color.yellow => return .{ .r = 255, .g = 255, .b = 0 },
        Color.green => return .{ .r = 0, .g = 255, .b = 0 },
        Color.purple => return .{ .r = 128, .g = 0, .b = 128 },
        Color.pink => return .{ .r = 255, .g = 192, .b = 203 },
        Color.red => return .{ .r = 255, .g = 0, .b = 0 },
        Color.white => return .{ .r = 255, .g = 255, .b = 255 },
        Color.dark_blue => return .{ .r = 0, .g = 0, .b = 102 },
    }
}

fn colorToInt(color: Color) u32 {
    switch (color) {
        Color.empty => return 0,
        Color.cyan => return 1,
        Color.blue => return 2,
        Color.orange => return 3,
        Color.yellow => return 4,
        Color.green => return 5,
        Color.purple => return 6,
        Color.pink => return 7,
        Color.red => return 8,
        Color.white => return 9,
        Color.dark_blue => return 10,
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

const Tetromino = struct {
    type: TetrominoType,
    // todo: this should be just a pointer to a global shape array
    shape: [4][4][4]Color,
    pos: Position,
    rotation: u32 = 0,

    pub fn rotate(self: *Tetromino) void {
        self.rotation = (self.rotation + 1) % 4;
    }
    pub fn left(self: *Tetromino) void {
        self.pos.y -= 1;
    }
    pub fn right(self: *Tetromino) void {
        self.pos.y += 1;
    }
    pub fn down(self: *Tetromino) void {
        self.pos.x += 1;
    }
};

fn getColor(ttype: TetrominoType) Color {
    switch (ttype) {
        TetrominoType.I => return TetrominoColors.I,
        TetrominoType.J => return TetrominoColors.J,
        TetrominoType.L => return TetrominoColors.L,
        TetrominoType.O => return TetrominoColors.O,
        TetrominoType.S => return TetrominoColors.S,
        TetrominoType.T => return TetrominoColors.T,
        TetrominoType.Z => return TetrominoColors.Z,
    }
}

fn isBitSetAtIndex(value: u16, index: usize) bool {
    assert(index < 16);
    const MaskInt = std.meta.Int(.unsigned, 16);
    const ShiftInt = std.math.Log2Int(MaskInt);
    const maskBit = @as(MaskInt, 1) << @as(ShiftInt, @intCast(index));
    return (value & maskBit) != 0;
}

fn tetrominoIndexTou16Index(row: usize, col: usize) usize {
    return 0xF - (row * 4 + col);
}

fn generateColoredTetrominoBufferFromShape(shape: u16, color: Color) [4][4]Color {
    var result: [4][4]Color = undefined;
    for (&result, 0..) |*row, row_idx| {
        for (row, 0..) |*cell, col_idx| {
            const index = tetrominoIndexTou16Index(row_idx, col_idx);
            if (isBitSetAtIndex(shape, index)) {
                cell.* = color;
            } else {
                cell.* = Color.empty;
            }
        }
    }
    return result;
}

const TetrominoShapes = struct {
    const I: [4]u16 = .{ 0x0F00, 0x2222, 0x00F0, 0x4444 };
    const J: [4]u16 = .{ 0x44C0, 0x8E00, 0x6440, 0x0E20 };
    const L: [4]u16 = .{ 0x4460, 0x0E80, 0xC440, 0x2E00 };
    const O: [4]u16 = .{ 0x6600, 0x6600, 0x6600, 0x6600 };
    const S: [4]u16 = .{ 0x06C0, 0x8C40, 0x6C00, 0x4620 };
    const T: [4]u16 = .{ 0x0E40, 0x4C40, 0x4E00, 0x4640 };
    const Z: [4]u16 = .{ 0x0C60, 0x4C80, 0xC600, 0x2640 };
};

fn getShape(ttype: TetrominoType) [4]u16 {
    switch (ttype) {
        TetrominoType.I => return TetrominoShapes.I,
        TetrominoType.J => return TetrominoShapes.J,
        TetrominoType.L => return TetrominoShapes.L,
        TetrominoType.O => return TetrominoShapes.O,
        TetrominoType.S => return TetrominoShapes.S,
        TetrominoType.T => return TetrominoShapes.T,
        TetrominoType.Z => return TetrominoShapes.Z,
    }
}

const TetrominoColors = struct {
    const I: Color = Color.cyan;
    const J: Color = Color.blue;
    const L: Color = Color.orange;
    const O: Color = Color.yellow;
    const S: Color = Color.green;
    const T: Color = Color.purple;
    const Z: Color = Color.pink;
};

fn printShapeAsBitMatrix(shape: u16) void {
    for (0..4) |row_idx| {
        for (0..4) |col_idx| {
            if (isBitSetAtIndex(shape, tetrominoIndexTou16Index(row_idx, col_idx))) {
                std.debug.print("1 ", .{});
            } else {
                std.debug.print("0 ", .{});
            }
        }
        std.debug.print("\n", .{});
    }
}

const BoardWidth = 20;
const BoardHeight = 26;
const InvisibleRows = 4;
const InvisibleCols = 4;

const Position = struct {
    x: usize,
    y: usize,
};

const Collision = enum {
    none,
    left_wall,
    right_wall,
    real,
};

const Board = struct {
    cells: [BoardHeight][BoardWidth]Color,

    // Commit the tetromino to the board
    pub fn landTetromino(self: *Board, tetromino: Tetromino) u32 {
        for (0..4) |row_idx| {
            for (0..4) |col_idx| {
                const pos = .{ .x = tetromino.pos.x + row_idx, .y = tetromino.pos.y + col_idx };
                if (isCellVisible(self, pos) and tetromino.shape[tetromino.rotation][row_idx][col_idx] != Color.empty) {
                    self.cells[pos.x][pos.y] = tetromino.shape[tetromino.rotation][row_idx][col_idx];
                }
            }
        }
        return self.clearFilledLines();
    }

    pub fn canPutTetromino(self: *Board, tetromino: Tetromino) bool {
        return self.collides(tetromino) == Collision.none;
    }

    pub fn collidesWithLeftWall(self: *Board, tetromino: Tetromino) bool {
        return self.collides(tetromino) == Collision.left_wall;
    }

    pub fn collidesWithRightWall(self: *Board, tetromino: Tetromino) bool {
        return self.collides(tetromino) == Collision.right_wall;
    }

    pub fn clear(self: *Board) void {
        self._clear(true);
    }

    fn collides(self: *Board, tetromino: Tetromino) Collision {
        for (0..4) |row_idx| {
            for (0..4) |col_idx| {
                const x = tetromino.pos.x + row_idx;
                const y = tetromino.pos.y + col_idx;
                const pos: Position = .{ .x = x, .y = y };
                if (tetromino.shape[tetromino.rotation][row_idx][col_idx] != Color.empty) {
                    if (self.isLeftWallCell(pos)) {
                        return Collision.left_wall;
                    }
                    if (self.isRightWallCell(pos)) {
                        return Collision.right_wall;
                    }
                    if (!isCellEmpty(self, pos)) {
                        return Collision.real;
                    }
                }
            }
        }
        return Collision.none;
    }

    fn _clear(self: *Board, clearVisible: bool) void {
        for (&self.cells, 0..) |*row, row_idx| {
            for (row, 0..) |*cell, col_idx| {
                if (isCellVisible(self, .{ .x = @intCast(row_idx), .y = @intCast(col_idx) })) {
                    if (clearVisible) {
                        cell.* = Color.empty;
                    } else {
                        // keep the color untouched
                    }
                } else {
                    cell.* = Color.red;
                }
            }
        }
    }

    pub fn isCellInvisible(self: *const Board, pos: Position) bool {
        return pos.x < InvisibleCols or pos.x >= BoardHeight - InvisibleRows or self.isLeftWallCell(pos) or self.isRightWallCell(pos);
    }

    pub fn isCellVisible(self: *const Board, pos: Position) bool {
        return !isCellInvisible(self, pos);
    }

    fn isLeftWallCell(_: *const Board, pos: Position) bool {
        return pos.y < InvisibleRows;
    }

    fn isRightWallCell(_: *const Board, pos: Position) bool {
        return pos.y >= BoardWidth - InvisibleRows;
    }

    pub fn dump(self: *const Board, printInvisible: bool) void {
        for (self.cells, 0..) |row, row_idx| {
            for (row, 0..) |cell, col_idx| {
                if (printInvisible or isCellVisible(self, .{ .x = @intCast(row_idx), .y = @intCast(col_idx) })) {
                    std.debug.print("{} ", .{colorToInt(cell)});
                }
            }
            std.debug.print("\n", .{});
        }
    }

    pub fn checksum(self: *const Board) u32 {
        var local_checksum: u32 = 0;
        for (self.cells) |row| {
            for (row) |cell| {
                local_checksum += colorToInt(cell);
            }
        }
        return local_checksum;
    }

    fn isCellEmpty(self: *const Board, pos: Position) bool {
        return self.cells[pos.x][pos.y] == Color.empty and isCellVisible(self, pos);
    }

    fn clearFilledLines(self: *Board) u32 {
        var lines_cleared: u32 = 0;
        for (0..BoardHeight) |row_idx| {
            var filled = true;
            const invisible_row = row_idx < InvisibleRows or row_idx >= BoardHeight - InvisibleRows;
            if (invisible_row) {
                filled = false;
            } else {
                for (0..BoardWidth) |col_idx| {
                    if (self.cells[row_idx][col_idx] == Color.empty) {
                        filled = false;
                        break;
                    }
                }
            }
            if (filled) {
                std.log.info("Clearing line {}", .{row_idx});
                lines_cleared += 1;
                for (0..BoardWidth) |col_idx| {
                    self.cells[row_idx][col_idx] = Color.empty;
                }
                // all the lines above were either not filled or cleared
                // we need to move them down
                var row_jdx = row_idx - 1;
                while (true) : (row_jdx -= 1) {
                    for (0..BoardWidth) |col_jdx| {
                        self.cells[row_jdx + 1][col_jdx] = self.cells[row_jdx][col_jdx];
                    }
                    if (row_jdx == InvisibleRows) break;
                }
            }
        }

        self._clear(false);
        std.log.info("Cleared {} lines", .{lines_cleared});
        return lines_cleared;
    }
};

fn u32ToString(value: u32, allocator: std.mem.Allocator) []const u8 {
    const result = std.fmt.allocPrint(allocator, "{d}", .{value}) catch @panic("Out of memory");
    return result;
}

fn concat2(allocator: std.mem.Allocator, s1: []const u8, s2: []const u8) []const u8 {
    const result = allocator.alloc(u8, s1.len + s2.len) catch @panic("Out of memory");
    @memcpy(result[0..s1.len], s1);
    @memcpy(result[s1.len..], s2);
    return result;
}

const Renderer = struct {
    renderer: *sdl.SDL_Renderer = undefined,
    window: *sdl.SDL_Window = undefined,
    debug: bool = false,
    arena: std.heap.ArenaAllocator = undefined,
    fba: std.heap.FixedBufferAllocator = undefined,
    font: *sdl.TTF_Font = undefined,

    level_text: [10]u8 = undefined,

    const cell_width = 25;
    const cell_height = 25;

    const hint_label_pos = Position{ .x = 1, .y = BoardWidth + (InvisibleCols * @as(i32, @intFromBool(DebugMode))) };
    const hint_pos = Position{ .x = 3, .y = BoardWidth + (InvisibleCols * @as(i32, @intFromBool(DebugMode))) };

    pub fn init(self: *Renderer, debug: bool) void {
        if (sdl.SDL_Init(sdl.SDL_INIT_VIDEO | sdl.SDL_INIT_TIMER) != 0) {
            std.log.err("Failed to initialize SDL: {*}\n", .{sdl.SDL_GetError()});
            sdl.SDL_Quit();
            return;
        }

        if (sdl.TTF_Init() != 0) {
            std.log.err("Failed to initialize TTF: {*}\n", .{sdl.SDL_GetError()});
            sdl.SDL_Quit();
            return;
        }

        self.window = sdl.SDL_CreateWindow("Tetris", sdl.SDL_WINDOWPOS_CENTERED, sdl.SDL_WINDOWPOS_CENTERED, 1000, 600, sdl.SDL_WINDOW_SHOWN) orelse {
            std.log.err("Failed to create window: {*}\n", .{sdl.SDL_GetError()});
            sdl.SDL_Quit();
            return;
        };

        self.renderer = sdl.SDL_CreateRenderer(self.window, -1, sdl.SDL_RENDERER_ACCELERATED) orelse {
            std.log.err("Failed to create renderer: {*}\n", .{sdl.SDL_GetError()});
            sdl.SDL_DestroyWindow(self.window);
            sdl.SDL_Quit();
            return;
        };

        self.arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        const alloc = self.arena.allocator();

        const tetris_root = std.fs.selfExeDirPathAlloc(alloc) catch @panic("Out of memory");
        defer alloc.free(tetris_root);

        const paths = &[_][]const u8{ tetris_root, "..", "assets", "font.ttf" };
        const path = std.fs.path.join(alloc, paths) catch @panic("Out of memory");
        std.log.info("path: {s}", .{path});

        self.font = sdl.TTF_OpenFont(path.ptr, 24) orelse {
            std.log.err("Failed to load font: {*}\n", .{sdl.SDL_GetError()});
            @panic("Failed to load font");
        };

        const level = 0;
        _ = std.fmt.bufPrint(&self.level_text, "Level: {}", .{level}) catch @panic("Out of memory");

        self.debug = debug;
    }

    const draw_internal_cells = false;

    pub fn drawBoard(self: *Renderer, board: Board) void {
        const boardColor = getRGB(Color.empty);
        const backgroundColor = getRGB(Color.dark_blue); // Use dark blue for background
        const draw_invisible = self.debug;

        _ = sdl.SDL_SetRenderDrawColor(self.renderer, backgroundColor.r, backgroundColor.g, backgroundColor.b, 255);
        _ = sdl.SDL_RenderClear(self.renderer);

        for (0..BoardHeight) |row_idx| {
            for (0..BoardWidth) |col_idx| {
                if (!draw_invisible and board.isCellInvisible(.{ .x = row_idx, .y = col_idx })) {
                    continue;
                }
                const cell = board.cells[row_idx][col_idx];
                const color = getRGB(cell);
                const rect = sdl.SDL_Rect{ .x = @intCast(col_idx * cell_width), .y = @intCast(row_idx * cell_height), .w = @intCast(cell_width), .h = @intCast(cell_height) };
                _ = sdl.SDL_SetRenderDrawColor(self.renderer, color.r, color.g, color.b, 255);
                _ = sdl.SDL_RenderFillRect(self.renderer, &rect);
                if (!board.isCellEmpty(.{ .x = row_idx, .y = col_idx }) or draw_internal_cells) {
                    _ = sdl.SDL_SetRenderDrawColor(self.renderer, boardColor.r, boardColor.g, boardColor.b, 255);
                    _ = sdl.SDL_RenderDrawRect(self.renderer, &rect);
                }
            }
        }
    }

    pub fn drawBoardBorder(self: *Renderer) void {
        const border_color = getRGB(Color.white);
        const border_rect = sdl.SDL_Rect{ .x = @intCast(InvisibleCols * cell_width), .y = @intCast(InvisibleRows * cell_height), .w = @intCast((BoardWidth - 2 * InvisibleCols) * cell_width), .h = @intCast((BoardHeight - 2 * InvisibleRows) * cell_height) };
        _ = sdl.SDL_SetRenderDrawColor(self.renderer, border_color.r, border_color.g, border_color.b, 255);
        _ = sdl.SDL_RenderDrawRect(self.renderer, &border_rect);
    }

    pub fn drawTetromino(self: *Renderer, tetromino: Tetromino) void {
        const bc = getRGB(Color.empty);
        for (0..4) |row_idx| {
            for (0..4) |col_idx| {
                const cell = tetromino.shape[tetromino.rotation][row_idx][col_idx];
                if (cell != Color.empty) {
                    const color = getRGB(cell);
                    const rect = sdl.SDL_Rect{ .x = @intCast((tetromino.pos.y + col_idx) * cell_width), .y = @intCast((tetromino.pos.x + row_idx) * cell_height), .w = @intCast(cell_width), .h = @intCast(cell_height) };
                    _ = sdl.SDL_SetRenderDrawColor(self.renderer, color.r, color.g, color.b, 255);
                    _ = sdl.SDL_RenderFillRect(self.renderer, &rect);
                    _ = sdl.SDL_SetRenderDrawColor(self.renderer, bc.r, bc.g, bc.b, 255);
                    _ = sdl.SDL_RenderDrawRect(self.renderer, &rect);
                }
            }
        }
    }

    pub fn drawGameOver(self: *Renderer) void {
        const color = getRGB(Color.red);
        const rect = sdl.SDL_Rect{ .x = 130, .y = 130, .w = 300, .h = 300 };
        _ = sdl.SDL_SetRenderDrawColor(self.renderer, color.r, color.g, color.b, 255);
        _ = sdl.SDL_RenderFillRect(self.renderer, &rect);

        const text = "Game Over";
        const rendered_text = sdl.TTF_RenderText_Solid(self.font, text, sdl.SDL_Color{ .r = 255, .g = 255, .b = 255, .a = 255 }) orelse {
            std.log.err("Failed to render text: {*}\n", .{sdl.SDL_GetError()});
            return;
        };

        const texture = sdl.SDL_CreateTextureFromSurface(self.renderer, rendered_text) orelse {
            std.log.err("Failed to create texture: {*}\n", .{sdl.SDL_GetError()});
            return;
        };

        const text_rect = sdl.SDL_Rect{ .x = 150, .y = 150, .w = 250, .h = 300 };
        _ = sdl.SDL_RenderCopy(self.renderer, texture, null, &text_rect);
        self.render();

        _ = sdl.SDL_DestroyTexture(texture);
        _ = sdl.SDL_FreeSurface(rendered_text);
    }

    pub fn drawNextTetrominoHint(self: *Renderer, tetromino: Tetromino) void {
        const hint_color = getRGB(Color.white);
        const hint_rect: sdl.SDL_Rect = sdl.SDL_Rect{ .x = @intCast(hint_label_pos.y * cell_width), .y = @intCast(hint_label_pos.x * cell_height), .w = @intCast(cell_width * 4), .h = @intCast(cell_height) };
        const hint_text = "Next";
        const rendered_hint_text = sdl.TTF_RenderText_Solid(self.font, hint_text, sdl.SDL_Color{ .r = hint_color.r, .g = hint_color.g, .b = hint_color.b, .a = 255 }) orelse {
            std.log.err("Failed to render text: {*}\n", .{sdl.SDL_GetError()});
            return;
        };

        const hint_texture = sdl.SDL_CreateTextureFromSurface(self.renderer, rendered_hint_text) orelse {
            std.log.err("Failed to create texture: {*}\n", .{sdl.SDL_GetError()});
            return;
        };

        _ = sdl.SDL_RenderCopy(self.renderer, hint_texture, null, &hint_rect);

        const bc = getRGB(Color.empty);
        for (0..4) |row_idx| {
            for (0..4) |col_idx| {
                const cell = tetromino.shape[tetromino.rotation][row_idx][col_idx];
                if (cell != Color.empty) {
                    const color = getRGB(cell);
                    const rect = sdl.SDL_Rect{ .x = @intCast((hint_pos.y + col_idx) * cell_width), .y = @intCast((hint_pos.x + row_idx) * cell_height), .w = @intCast(cell_width), .h = @intCast(cell_height) };
                    _ = sdl.SDL_SetRenderDrawColor(self.renderer, color.r, color.g, color.b, 255);
                    _ = sdl.SDL_RenderFillRect(self.renderer, &rect);
                    _ = sdl.SDL_SetRenderDrawColor(self.renderer, bc.r, bc.g, bc.b, 255);
                    _ = sdl.SDL_RenderDrawRect(self.renderer, &rect);
                }
            }
        }

        // self.render();

        _ = sdl.SDL_DestroyTexture(hint_texture);
        _ = sdl.SDL_FreeSurface(rendered_hint_text);
    }

    pub fn drawLevelAndScore(self: *Renderer, level: u32, score: u32) void {
        const level_color = getRGB(Color.white);
        const level_str = std.fmt.bufPrint(&self.level_text, "Level: {}", .{level}) catch @panic("Out of memory");
        const info_text_pos_start = Position{ .x = hint_label_pos.x, .y = hint_label_pos.y + 5 };
        const level_text_rect = sdl.SDL_Rect{ .x = @intCast((info_text_pos_start.y) * cell_width), .y = @intCast((info_text_pos_start.x) * cell_height), .w = @intCast(cell_width * 4), .h = @intCast(cell_height) };
        const rendered_level_text = sdl.TTF_RenderText_Solid(self.font, level_str.ptr, sdl.SDL_Color{ .r = level_color.r, .g = level_color.g, .b = level_color.b, .a = 255 }) orelse {
            std.log.err("Failed to render text: {*}\n", .{sdl.SDL_GetError()});
            return;
        };

        const level_texture = sdl.SDL_CreateTextureFromSurface(self.renderer, rendered_level_text) orelse {
            std.log.err("Failed to create texture: {*}\n", .{sdl.SDL_GetError()});
            return;
        };

        _ = sdl.SDL_RenderCopy(self.renderer, level_texture, null, &level_text_rect);

        const score_color = getRGB(Color.white);
        const score_text = "Score: ";
        const score_value = u32ToString(score, self.arena.allocator());
        defer self.arena.allocator().free(score_value);
        const score_text_rect = sdl.SDL_Rect{ .x = @intCast((info_text_pos_start.y) * cell_width), .y = @intCast((info_text_pos_start.x + 2) * cell_height), .w = @intCast(cell_width * 4), .h = @intCast(cell_height) };
        const rendered_score_text = sdl.TTF_RenderText_Solid(self.font, score_text.ptr, sdl.SDL_Color{ .r = score_color.r, .g = score_color.g, .b = score_color.b, .a = 255 }) orelse {
            std.log.err("Failed to render text: {*}\n", .{sdl.SDL_GetError()});
            return;
        };

        const score_texture = sdl.SDL_CreateTextureFromSurface(self.renderer, rendered_score_text) orelse {
            std.log.err("Failed to create texture: {*}\n", .{sdl.SDL_GetError()});
            return;
        };

        _ = sdl.SDL_RenderCopy(self.renderer, score_texture, null, &score_text_rect);

        const score_value_rect = sdl.SDL_Rect{ .x = @intCast((info_text_pos_start.y + 6) * cell_width), .y = @intCast((info_text_pos_start.x + 2) * cell_height), .w = @intCast(cell_width * 4), .h = @intCast(cell_height) };
        const rendered_score_value_text = sdl.TTF_RenderText_Solid(self.font, score_value.ptr, sdl.SDL_Color{ .r = score_color.r, .g = score_color.g, .b = score_color.b, .a = 255 }) orelse {
            std.log.err("Failed to render text: {*}\n", .{sdl.SDL_GetError()});
            return;
        };

        const score_value_texture = sdl.SDL_CreateTextureFromSurface(self.renderer, rendered_score_value_text) orelse {
            std.log.err("Failed to create texture: {*}\n", .{sdl.SDL_GetError()});
            return;
        };

        _ = sdl.SDL_RenderCopy(self.renderer, score_value_texture, null, &score_value_rect);

        self.render();

        _ = sdl.SDL_DestroyTexture(level_texture);
        _ = sdl.SDL_FreeSurface(rendered_level_text);
        _ = sdl.SDL_DestroyTexture(score_texture);
        _ = sdl.SDL_FreeSurface(rendered_score_text);
        _ = sdl.SDL_DestroyTexture(score_value_texture);
        _ = sdl.SDL_FreeSurface(rendered_score_value_text);
    }

    pub fn render(self: *Renderer) void {
        sdl.SDL_RenderPresent(self.renderer);
    }

    pub fn destroy(self: *Renderer) void {
        self.arena.deinit();
        sdl.SDL_DestroyRenderer(self.renderer);
        sdl.SDL_DestroyWindow(self.window);
        sdl.SDL_Quit();
    }
};

const TimerInterval = 1000;

const Game = struct {
    state: GameState,
    board: Board,
    renderer: Renderer,
    timer_id: sdl.SDL_TimerID = 0,

    pub fn init(self: *Game) void {
        self.state.init();
        self.board.clear();
        self.renderer.init(DebugMode);
        self.timer_id = sdl.SDL_AddTimer(TimerInterval, timerCallback, null);
    }

    pub fn run(self: *Game) void {
        while (self.state.state != GameStateEnum.quit) {
            if (self.state.state == GameStateEnum.game_over) {
                std.log.info("Game over", .{});
                self.renderer.drawGameOver();
                std.time.sleep(std.math.pow(u64, 10, 8));
                self.registerInputs();
                self.handleInput();
            } else {
                self.registerInputs();
                self.renderer.drawBoard(self.board);
                self.renderer.drawTetromino(self.state.current_tetromino);
                self.renderer.drawBoardBorder();
                self.renderer.drawNextTetrominoHint(self.state.next_tetromino);
                self.renderer.drawLevelAndScore(self.state.level, self.state.score);
                self.renderer.render();
                self.handleInput();
            }
        }
        self.renderer.destroy();
    }

    fn registerInputs(self: *Game) void {
        var event: sdl.SDL_Event = undefined;
        while (sdl.SDL_PollEvent(&event) != 0) {
            switch (event.type) {
                sdl.SDL_QUIT => self.state.quit(),
                sdl.SDL_KEYDOWN => {
                    const sym = event.key.keysym.sym;
                    self.state.keys.put(sym, true) catch @panic("Out of memory");
                },
                sdl.SDL_KEYUP => {
                    const sym = event.key.keysym.sym;
                    self.state.keys.put(sym, false) catch @panic("Out of memory");
                },
                sdl.SDL_USEREVENT => {
                    if (self.state.state == GameStateEnum.game_over) {
                        return;
                    }
                    // todo: this should just store the action. Hadling should happen in `handleInput`.
                    self.state.current_tetromino.down();
                    std.log.debug("Event tick to move down", .{});
                    // If we cannot move the tetromino down, we land it and generate a new one.
                    self.maybeLandTetromino();
                },
                else => {},
            }
        }
    }

    fn maybeLandTetromino(self: *Game) void {
        if (!self.board.canPutTetromino(self.state.current_tetromino)) {
            std.log.debug("Can't move the current tetromino down. Landing it.", .{});
            self.state.current_tetromino.pos.x -= 1;
            const lines_cleared = self.board.landTetromino(self.state.current_tetromino);
            self.state.current_tetromino = self.state.next_tetromino;
            self.state.next_tetromino = self.state.generateTetromino();
            if (!self.board.canPutTetromino(self.state.current_tetromino)) {
                self.state.gameover();
            }
            self.state.updateScore(lines_cleared);
            self.updateTimer();
        }
    }

    fn getTimerValueFromLevel(self: *Game) u32 {
        return TimerInterval - (self.state.level * 45);
    }

    fn updateTimer(self: *Game) void {
        _ = sdl.SDL_RemoveTimer(self.timer_id);
        self.timer_id = sdl.SDL_AddTimer(self.getTimerValueFromLevel(), timerCallback, null);
    }

    fn handleInput(self: *Game) void {
        if (self.state.keys.get(sdl.SDLK_LEFT) orelse false) {
            self.state.current_tetromino.left();
            std.log.debug("Trying to move the current tetromino left. Position [{}, {}]", .{ self.state.current_tetromino.pos.x, self.state.current_tetromino.pos.y });
            if (!self.board.canPutTetromino(self.state.current_tetromino)) {
                self.state.current_tetromino.right();
                std.log.debug("Can't move the current tetromino left. Restored position [{}, {}]", .{ self.state.current_tetromino.pos.x, self.state.current_tetromino.pos.y });
            }
            self.state.keys.put(sdl.SDLK_LEFT, false) catch @panic("Out of memory");
        }
        if (self.state.keys.get(sdl.SDLK_RIGHT) orelse false) {
            self.state.current_tetromino.right();
            std.log.debug("Trying to move the current tetromino right. Position [{}, {}]", .{ self.state.current_tetromino.pos.x, self.state.current_tetromino.pos.y });
            if (!self.board.canPutTetromino(self.state.current_tetromino)) {
                self.state.current_tetromino.left();
                std.log.info("Can't move the current tetromino right. Restored position [{}, {}]", .{ self.state.current_tetromino.pos.x, self.state.current_tetromino.pos.y });
            }
            self.state.keys.put(sdl.SDLK_RIGHT, false) catch @panic("Out of memory");
        }
        if (self.state.keys.get(sdl.SDLK_ESCAPE) orelse false) {
            self.state.quit();
        }
        if (self.state.keys.get(sdl.SDLK_DOWN) orelse false) {
            self.state.current_tetromino.down();
            std.log.debug("Trying to move the current tetromino down. Position [{}, {}]", .{ self.state.current_tetromino.pos.x, self.state.current_tetromino.pos.y });
            self.maybeLandTetromino();
            self.state.keys.put(sdl.SDLK_DOWN, false) catch @panic("Out of memory");
        }
        if (self.state.keys.get(sdl.SDLK_UP) orelse false) {
            self.state.current_tetromino.rotate();
            if (self.board.collidesWithLeftWall(self.state.current_tetromino)) {
                // try to move the tetromino to the right
                self.state.current_tetromino.right();
                // For the I tetromino, we might need to move it to the left twice
                // terrible hack, but I can generate all the code with copilot! yay!
                if (self.state.current_tetromino.type == TetrominoType.I and self.board.collidesWithLeftWall(self.state.current_tetromino)) {
                    self.state.current_tetromino.right();
                    if (self.board.canPutTetromino(self.state.current_tetromino)) {
                        std.log.debug("Moved the current tetromino to the right to rotate it. Position [{}, {}]", .{ self.state.current_tetromino.pos.x, self.state.current_tetromino.pos.y });
                    } else {
                        self.state.current_tetromino.left();
                        self.state.current_tetromino.left();
                        std.log.debug("Can't move the current tetromino to the right to rotate it. Restored position [{}, {}]", .{ self.state.current_tetromino.pos.x, self.state.current_tetromino.pos.y });
                        self.state.current_tetromino.rotate();
                        self.state.current_tetromino.rotate();
                        self.state.current_tetromino.rotate();
                    }
                } else if (self.board.canPutTetromino(self.state.current_tetromino)) {
                    std.log.debug("Moved the current tetromino to the right to rotate it. Position [{}, {}]", .{ self.state.current_tetromino.pos.x, self.state.current_tetromino.pos.y });
                } else {
                    self.state.current_tetromino.left();
                    std.log.debug("Can't move the current tetromino to the right to rotate it. Restored position [{}, {}]", .{ self.state.current_tetromino.pos.x, self.state.current_tetromino.pos.y });
                    self.state.current_tetromino.rotate();
                    self.state.current_tetromino.rotate();
                    self.state.current_tetromino.rotate();
                }
            } else if (self.board.collidesWithRightWall(self.state.current_tetromino)) {
                // try to move the tetromino to the left
                self.state.current_tetromino.left();
                // For the I tetromino, we might need to move it to the right twice
                // terrible hack, but I can generate all the code with copilot! yay!
                if (self.state.current_tetromino.type == TetrominoType.I and self.board.collidesWithRightWall(self.state.current_tetromino)) {
                    self.state.current_tetromino.left();
                    if (self.board.canPutTetromino(self.state.current_tetromino)) {
                        std.log.debug("Moved the current tetromino to the left to rotate it. Position [{}, {}]", .{ self.state.current_tetromino.pos.x, self.state.current_tetromino.pos.y });
                    } else {
                        self.state.current_tetromino.right();
                        self.state.current_tetromino.right();
                        std.log.debug("Can't move the current tetromino to the left to rotate it. Restored position [{}, {}]", .{ self.state.current_tetromino.pos.x, self.state.current_tetromino.pos.y });
                        self.state.current_tetromino.rotate();
                        self.state.current_tetromino.rotate();
                        self.state.current_tetromino.rotate();
                    }
                } else if (self.board.canPutTetromino(self.state.current_tetromino)) {
                    std.log.debug("Moved the current tetromino to the left to rotate it. Position [{}, {}]", .{ self.state.current_tetromino.pos.x, self.state.current_tetromino.pos.y });
                } else {
                    self.state.current_tetromino.right();
                    std.log.debug("Can't move the current tetromino to the left to rotate it. Restored position [{}, {}]", .{ self.state.current_tetromino.pos.x, self.state.current_tetromino.pos.y });
                    self.state.current_tetromino.rotate();
                    self.state.current_tetromino.rotate();
                    self.state.current_tetromino.rotate();
                }
                if (self.board.canPutTetromino(self.state.current_tetromino)) {
                    std.log.debug("Moved the current tetromino to the left to rotate it. Position [{}, {}]", .{ self.state.current_tetromino.pos.x, self.state.current_tetromino.pos.y });
                } else {
                    self.state.current_tetromino.right();
                    std.log.debug("Can't move the current tetromino to the left to rotate it. Restored position [{}, {}]", .{ self.state.current_tetromino.pos.x, self.state.current_tetromino.pos.y });
                    self.state.current_tetromino.rotate();
                    self.state.current_tetromino.rotate();
                    self.state.current_tetromino.rotate();
                }
            } else if (!self.board.canPutTetromino(self.state.current_tetromino)) {
                self.state.current_tetromino.rotate();
                self.state.current_tetromino.rotate();
                self.state.current_tetromino.rotate();
            }
            self.state.keys.put(sdl.SDLK_UP, false) catch @panic("Out of memory");
        }
    }
};

fn timerCallback(interval: u32, _: ?*anyopaque) callconv(.C) u32 {
    var event: sdl.SDL_Event = undefined;
    event.type = sdl.SDL_USEREVENT;
    _ = sdl.SDL_PushEvent(&event);
    return interval;
}

pub fn main() !void {
    // todo: put inside the game
    var game: Game = .{ .board = .{ .cells = undefined }, .state = .{}, .renderer = .{} };
    game.init();
    game.run();
}

test "test RGB" {
    try expect(getRGB(Color.empty).r == 0);
    try expect(getRGB(Color.empty).g == 0);
    try expect(getRGB(Color.empty).b == 0);

    try expect(getRGB(Color.cyan).r == 0);
    try expect(getRGB(Color.cyan).g == 255);
    try expect(getRGB(Color.cyan).b == 255);

    try expect(getRGB(Color.blue).r == 0);
    try expect(getRGB(Color.blue).g == 0);
    try expect(getRGB(Color.blue).b == 255);

    try expect(getRGB(Color.orange).r == 255);
    try expect(getRGB(Color.orange).g == 165);
    try expect(getRGB(Color.orange).b == 0);

    try expect(getRGB(Color.yellow).r == 255);
    try expect(getRGB(Color.yellow).g == 255);
    try expect(getRGB(Color.yellow).b == 0);

    try expect(getRGB(Color.green).r == 0);
    try expect(getRGB(Color.green).g == 255);
    try expect(getRGB(Color.green).b == 0);

    try expect(getRGB(Color.purple).r == 128);
    try expect(getRGB(Color.purple).g == 0);
    try expect(getRGB(Color.purple).b == 128);

    try expect(getRGB(Color.pink).r == 255);
    try expect(getRGB(Color.pink).g == 192);
    try expect(getRGB(Color.pink).b == 203);

    try expect(getRGB(Color.red).r == 255);
    try expect(getRGB(Color.red).g == 0);
    try expect(getRGB(Color.red).b == 0);

    try expect(getRGB(Color.white).r == 255);
    try expect(getRGB(Color.white).g == 255);
    try expect(getRGB(Color.white).b == 255);

    try expect(getRGB(Color.dark_blue).r == 0);
    try expect(getRGB(Color.dark_blue).g == 0);
    try expect(getRGB(Color.dark_blue).b == 139);
}

test "Cell visible" {
    var board = Board{ .cells = undefined };
    try expect(board.isCellVisible(Position{ .x = 0, .y = 0 }) == false);
    try expect(board.isCellVisible(Position{ .x = 1, .y = 1 }) == false);
    try expect(board.isCellVisible(Position{ .x = InvisibleCols, .y = InvisibleRows }) == true);
    try expect(board.isCellVisible(Position{ .x = BoardHeight - 1, .y = BoardWidth - 1 }) == false);
}

test "Clear board checksum" {
    var board = Board{ .cells = undefined };
    board.clear();
    const checksum: u32 = board.checksum();
    const expected_checksum = (InvisibleCols * BoardHeight * 2 + InvisibleRows * BoardWidth * 2 - InvisibleCols * InvisibleRows * 4) * colorToInt(Color.red);
    try expect(checksum == expected_checksum);
}

test "Generate tetromino rotations" {
    const I0 = 0x0F00;
    const I1 = 0x2222;
    const I2 = 0x00F0;
    const I3 = 0x4444;

    const bufI0: [4][4]Color = generateColoredTetrominoBufferFromShape(I0, Color.cyan);
    const bufI1 = generateColoredTetrominoBufferFromShape(I1, Color.cyan);
    const bufI2 = generateColoredTetrominoBufferFromShape(I2, Color.cyan);
    const bufI3 = generateColoredTetrominoBufferFromShape(I3, Color.cyan);

    const expectedI0: [4][4]Color = .{ .{ Color.empty, Color.empty, Color.empty, Color.empty }, .{ Color.cyan, Color.cyan, Color.cyan, Color.cyan }, .{ Color.empty, Color.empty, Color.empty, Color.empty }, .{ Color.empty, Color.empty, Color.empty, Color.empty } };
    const expectedI1: [4][4]Color = .{ .{ Color.empty, Color.empty, Color.cyan, Color.empty }, .{ Color.empty, Color.empty, Color.cyan, Color.empty }, .{ Color.empty, Color.empty, Color.cyan, Color.empty }, .{ Color.empty, Color.empty, Color.cyan, Color.empty } };
    const expectedI2: [4][4]Color = .{ .{ Color.empty, Color.empty, Color.empty, Color.empty }, .{ Color.empty, Color.empty, Color.empty, Color.empty }, .{ Color.cyan, Color.cyan, Color.cyan, Color.cyan }, .{ Color.empty, Color.empty, Color.empty, Color.empty } };
    const expectedI3: [4][4]Color = .{ .{ Color.empty, Color.cyan, Color.empty, Color.empty }, .{ Color.empty, Color.cyan, Color.empty, Color.empty }, .{ Color.empty, Color.cyan, Color.empty, Color.empty }, .{ Color.empty, Color.cyan, Color.empty, Color.empty } };

    try expect(std.mem.eql(Color, bufI0[0][0..], expectedI0[0][0..]));
    try expect(std.mem.eql(Color, bufI0[1][0..], expectedI0[1][0..]));
    try expect(std.mem.eql(Color, bufI0[2][0..], expectedI0[2][0..]));
    try expect(std.mem.eql(Color, bufI0[3][0..], expectedI0[3][0..]));

    try expect(std.mem.eql(Color, bufI1[0][0..], expectedI1[0][0..]));
    try expect(std.mem.eql(Color, bufI1[1][0..], expectedI1[1][0..]));
    try expect(std.mem.eql(Color, bufI1[2][0..], expectedI1[2][0..]));
    try expect(std.mem.eql(Color, bufI1[3][0..], expectedI1[3][0..]));

    try expect(std.mem.eql(Color, bufI2[0][0..], expectedI2[0][0..]));
    try expect(std.mem.eql(Color, bufI2[1][0..], expectedI2[1][0..]));
    try expect(std.mem.eql(Color, bufI2[2][0..], expectedI2[2][0..]));
    try expect(std.mem.eql(Color, bufI2[3][0..], expectedI2[3][0..]));

    try expect(std.mem.eql(Color, bufI3[0][0..], expectedI3[0][0..]));
    try expect(std.mem.eql(Color, bufI3[1][0..], expectedI3[1][0..]));
    try expect(std.mem.eql(Color, bufI3[2][0..], expectedI3[2][0..]));
    try expect(std.mem.eql(Color, bufI3[3][0..], expectedI3[3][0..]));
}

test "land tetromino" {
    var board = Board{ .cells = undefined };
    board.clear();
}
