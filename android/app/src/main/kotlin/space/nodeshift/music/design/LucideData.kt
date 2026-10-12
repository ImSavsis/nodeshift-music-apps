package space.nodeshift.music.design

sealed interface IconNode {
    data class PathData(val d: String) : IconNode
    data class Circle(val cx: Float, val cy: Float, val r: Float) : IconNode
    data class Line(val x1: Float, val y1: Float, val x2: Float, val y2: Float) : IconNode
    data class Polyline(val points: String) : IconNode
    data class Polygon(val points: String) : IconNode
    data class Rect(val x: Float, val y: Float, val width: Float, val height: Float, val rx: Float) : IconNode
}

enum class LucideName(val nodes: List<IconNode>) {
    ArrowDownToLine(
        listOf(
            IconNode.PathData("M12 17V3"),
            IconNode.PathData("m6 11 6 6 6-6"),
            IconNode.PathData("M19 21H5"),
        ),
    ),
    Bookmark(
        listOf(
            IconNode.PathData("m19 21-7-4-7 4V5a2 2 0 0 1 2-2h10a2 2 0 0 1 2 2v16z"),
        ),
    ),
    Calendar(
        listOf(
            IconNode.PathData("M8 2v4"),
            IconNode.PathData("M16 2v4"),
            IconNode.Rect(3f, 4f, 18f, 18f, 2f),
            IconNode.PathData("M3 10h18"),
        ),
    ),
    Camera(
        listOf(
            IconNode.PathData("M14.5 4h-5L7 7H4a2 2 0 0 0-2 2v9a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2V9a2 2 0 0 0-2-2h-3l-2.5-3z"),
            IconNode.Circle(12f, 13f, 3f),
        ),
    ),
    Check(
        listOf(
            IconNode.PathData("M20 6 9 17l-5-5"),
        ),
    ),
    ChevronDown(
        listOf(
            IconNode.PathData("m6 9 6 6 6-6"),
        ),
    ),
    ChevronUp(
        listOf(
            IconNode.PathData("m18 15-6-6-6 6"),
        ),
    ),
    ChevronRight(
        listOf(
            IconNode.PathData("m9 18 6-6-6-6"),
        ),
    ),
    ChevronLeft(
        listOf(
            IconNode.PathData("m15 18-6-6 6-6"),
        ),
    ),
    CircleAlert(
        listOf(
            IconNode.Circle(12f, 12f, 10f),
            IconNode.Line(12f, 8f, 12f, 12f),
            IconNode.Line(12f, 16f, 12.01f, 16f),
        ),
    ),
    Clapperboard(
        listOf(
            IconNode.PathData("M20.2 6 3 11l-.9-2.4c-.3-1.1.3-2.2 1.3-2.5l13.5-4c1.1-.3 2.2.3 2.5 1.3Z"),
            IconNode.PathData("m6.2 5.3 3.1 3.9"),
            IconNode.PathData("m12.4 3.4 3.1 4"),
            IconNode.PathData("M3 11h18v8a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2Z"),
        ),
    ),
    CloudDownload(
        listOf(
            IconNode.PathData("M12 13v8l-4-4"),
            IconNode.PathData("m12 21 4-4"),
            IconNode.PathData("M4.393 15.269A7 7 0 1 1 15.71 8h1.79a4.5 4.5 0 0 1 2.436 8.284"),
        ),
    ),
    Copy(
        listOf(
            IconNode.Rect(8f, 8f, 14f, 14f, 2f),
            IconNode.PathData("M4 16c-1.1 0-2-.9-2-2V4c0-1.1.9-2 2-2h10c1.1 0 2 .9 2 2"),
        ),
    ),
    Ellipsis(
        listOf(
            IconNode.Circle(12f, 12f, 1f),
            IconNode.Circle(19f, 12f, 1f),
            IconNode.Circle(5f, 12f, 1f),
        ),
    ),
    ExternalLink(
        listOf(
            IconNode.PathData("M15 3h6v6"),
            IconNode.PathData("M10 14 21 3"),
            IconNode.PathData("M18 13v6a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h6"),
        ),
    ),
    FileText(
        listOf(
            IconNode.PathData("M15 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V7Z"),
            IconNode.PathData("M14 2v4a2 2 0 0 0 2 2h4"),
            IconNode.PathData("M10 9H8"),
            IconNode.PathData("M16 13H8"),
            IconNode.PathData("M16 17H8"),
        ),
    ),
    FolderUp(
        listOf(
            IconNode.PathData("M20 20a2 2 0 0 0 2-2V8a2 2 0 0 0-2-2h-7.9a2 2 0 0 1-1.69-.9L9.6 3.9A2 2 0 0 0 7.93 3H4a2 2 0 0 0-2 2v13a2 2 0 0 0 2 2Z"),
            IconNode.PathData("M12 10v6"),
            IconNode.PathData("m9 13 3-3 3 3"),
        ),
    ),
    HardDrive(
        listOf(
            IconNode.Line(22f, 12f, 2f, 12f),
            IconNode.PathData("M5.45 5.11 2 12v6a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2v-6l-3.45-6.89A2 2 0 0 0 16.76 4H7.24a2 2 0 0 0-1.79 1.11z"),
            IconNode.Line(6f, 16f, 6.01f, 16f),
            IconNode.Line(10f, 16f, 10.01f, 16f),
        ),
    ),
    Heart(
        listOf(
            IconNode.PathData("M19 14c1.49-1.46 3-3.21 3-5.5A5.5 5.5 0 0 0 16.5 3c-1.76 0-3 .5-4.5 2-1.5-1.5-2.74-2-4.5-2A5.5 5.5 0 0 0 2 8.5c0 2.3 1.5 4.05 3 5.5l7 7Z"),
        ),
    ),
    ImagePlus(
        listOf(
            IconNode.PathData("M16 5h6"),
            IconNode.PathData("M19 2v6"),
            IconNode.PathData("M21 11.5V19a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h7.5"),
            IconNode.PathData("m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"),
            IconNode.Circle(9f, 9f, 2f),
        ),
    ),
    Keyboard(
        listOf(
            IconNode.PathData("M10 8h.01"),
            IconNode.PathData("M12 12h.01"),
            IconNode.PathData("M14 8h.01"),
            IconNode.PathData("M16 12h.01"),
            IconNode.PathData("M18 8h.01"),
            IconNode.PathData("M6 8h.01"),
            IconNode.PathData("M7 16h10"),
            IconNode.PathData("M8 12h.01"),
            IconNode.Rect(2f, 4f, 20f, 16f, 2f),
        ),
    ),
    LayoutGrid(
        listOf(
            IconNode.Rect(3f, 3f, 7f, 7f, 1f),
            IconNode.Rect(14f, 3f, 7f, 7f, 1f),
            IconNode.Rect(14f, 14f, 7f, 7f, 1f),
            IconNode.Rect(3f, 14f, 7f, 7f, 1f),
        ),
    ),
    LayoutList(
        listOf(
            IconNode.Rect(3f, 3f, 7f, 7f, 1f),
            IconNode.Rect(3f, 14f, 7f, 7f, 1f),
            IconNode.PathData("M14 4h7"),
            IconNode.PathData("M14 9h7"),
            IconNode.PathData("M14 15h7"),
            IconNode.PathData("M14 20h7"),
        ),
    ),
    Link(
        listOf(
            IconNode.PathData("M10 13a5 5 0 0 0 7.54.54l3-3a5 5 0 0 0-7.07-7.07l-1.72 1.71"),
            IconNode.PathData("M14 11a5 5 0 0 0-7.54-.54l-3 3a5 5 0 0 0 7.07 7.07l1.71-1.71"),
        ),
    ),
    ListEnd(
        listOf(
            IconNode.PathData("M16 12H3"),
            IconNode.PathData("M16 6H3"),
            IconNode.PathData("M10 18H3"),
            IconNode.PathData("M21 6v10a2 2 0 0 1-2 2h-5"),
            IconNode.PathData("m16 16-2 2 2 2"),
        ),
    ),
    ListMusic(
        listOf(
            IconNode.PathData("M21 15V6"),
            IconNode.PathData("M18.5 18a2.5 2.5 0 1 0 0-5 2.5 2.5 0 0 0 0 5Z"),
            IconNode.PathData("M12 12H3"),
            IconNode.PathData("M16 6H3"),
            IconNode.PathData("M12 18H3"),
        ),
    ),
    ListStart(
        listOf(
            IconNode.PathData("M16 12H3"),
            IconNode.PathData("M16 18H3"),
            IconNode.PathData("M10 6H3"),
            IconNode.PathData("M21 18V8a2 2 0 0 0-2-2h-5"),
            IconNode.PathData("m16 8-2-2 2-2"),
        ),
    ),
    LogIn(
        listOf(
            IconNode.PathData("M15 3h4a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2h-4"),
            IconNode.Polyline("10 17 15 12 10 7"),
            IconNode.Line(15f, 12f, 3f, 12f),
        ),
    ),
    LogOut(
        listOf(
            IconNode.PathData("M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4"),
            IconNode.Polyline("16 17 21 12 16 7"),
            IconNode.Line(21f, 12f, 9f, 12f),
        ),
    ),
    Maximize2(
        listOf(
            IconNode.Polyline("15 3 21 3 21 9"),
            IconNode.Polyline("9 21 3 21 3 15"),
            IconNode.Line(21f, 3f, 14f, 10f),
            IconNode.Line(3f, 21f, 10f, 14f),
        ),
    ),
    MicOff(
        listOf(
            IconNode.Line(2f, 2f, 22f, 22f),
            IconNode.PathData("M18.89 13.23A7.12 7.12 0 0 0 19 12v-2"),
            IconNode.PathData("M5 10v2a7 7 0 0 0 12 5"),
            IconNode.PathData("M15 9.34V5a3 3 0 0 0-5.68-1.33"),
            IconNode.PathData("M9 9v3a3 3 0 0 0 5.12 2.12"),
            IconNode.Line(12f, 19f, 12f, 22f),
        ),
    ),
    Music2(
        listOf(
            IconNode.Circle(8f, 18f, 4f),
            IconNode.PathData("M12 18V2l7 4"),
        ),
    ),
    Pause(
        listOf(
            IconNode.Rect(14f, 4f, 4f, 16f, 1f),
            IconNode.Rect(6f, 4f, 4f, 16f, 1f),
        ),
    ),
    Pencil(
        listOf(
            IconNode.PathData("M21.174 6.812a1 1 0 0 0-3.986-3.987L3.842 16.174a2 2 0 0 0-.5.83l-1.321 4.352a.5.5 0 0 0 .623.622l4.353-1.32a2 2 0 0 0 .83-.497z"),
            IconNode.PathData("m15 5 4 4"),
        ),
    ),
    Play(
        listOf(
            IconNode.Polygon("6 3 20 12 6 21 6 3"),
        ),
    ),
    Plus(
        listOf(
            IconNode.PathData("M5 12h14"),
            IconNode.PathData("M12 5v14"),
        ),
    ),
    Repeat(
        listOf(
            IconNode.PathData("m17 2 4 4-4 4"),
            IconNode.PathData("M3 11v-1a4 4 0 0 1 4-4h14"),
            IconNode.PathData("m7 22-4-4 4-4"),
            IconNode.PathData("M21 13v1a4 4 0 0 1-4 4H3"),
        ),
    ),
    Repeat1(
        listOf(
            IconNode.PathData("m17 2 4 4-4 4"),
            IconNode.PathData("M3 11v-1a4 4 0 0 1 4-4h14"),
            IconNode.PathData("m7 22-4-4 4-4"),
            IconNode.PathData("M21 13v1a4 4 0 0 1-4 4H3"),
            IconNode.PathData("M11 10h1v4"),
        ),
    ),
    Search(
        listOf(
            IconNode.Circle(11f, 11f, 8f),
            IconNode.PathData("m21 21-4.3-4.3"),
        ),
    ),
    Shuffle(
        listOf(
            IconNode.PathData("M2 18h1.4c1.3 0 2.5-.6 3.3-1.7l6.1-8.6c.7-1.1 2-1.7 3.3-1.7H22"),
            IconNode.PathData("m18 2 4 4-4 4"),
            IconNode.PathData("M2 6h1.9c1.5 0 2.9.9 3.6 2.2"),
            IconNode.PathData("M22 18h-5.9c-1.3 0-2.6-.7-3.3-1.8l-.5-.8"),
            IconNode.PathData("m18 14 4 4-4 4"),
        ),
    ),
    SkipBack(
        listOf(
            IconNode.Polygon("19 20 9 12 19 4 19 20"),
            IconNode.Line(5f, 19f, 5f, 5f),
        ),
    ),
    SkipForward(
        listOf(
            IconNode.Polygon("5 4 15 12 5 20 5 4"),
            IconNode.Line(19f, 5f, 19f, 19f),
        ),
    ),
    Sparkles(
        listOf(
            IconNode.PathData("M9.937 15.5A2 2 0 0 0 8.5 14.063l-6.135-1.582a.5.5 0 0 1 0-.962L8.5 9.936A2 2 0 0 0 9.937 8.5l1.582-6.135a.5.5 0 0 1 .963 0L14.063 8.5A2 2 0 0 0 15.5 9.937l6.135 1.581a.5.5 0 0 1 0 .964L15.5 14.063a2 2 0 0 0-1.437 1.437l-1.582 6.135a.5.5 0 0 1-.963 0z"),
            IconNode.PathData("M20 3v4"),
            IconNode.PathData("M22 5h-4"),
            IconNode.PathData("M4 17v2"),
            IconNode.PathData("M5 18H3"),
        ),
    ),
    Trash2(
        listOf(
            IconNode.PathData("M3 6h18"),
            IconNode.PathData("M19 6v14c0 1-1 2-2 2H7c-1 0-2-1-2-2V6"),
            IconNode.PathData("M8 6V4c0-1 1-2 2-2h4c1 0 2 1 2 2v2"),
            IconNode.Line(10f, 11f, 10f, 17f),
            IconNode.Line(14f, 11f, 14f, 17f),
        ),
    ),
    Trophy(
        listOf(
            IconNode.PathData("M6 9H4.5a2.5 2.5 0 0 1 0-5H6"),
            IconNode.PathData("M18 9h1.5a2.5 2.5 0 0 0 0-5H18"),
            IconNode.PathData("M4 22h16"),
            IconNode.PathData("M10 14.66V17c0 .55-.47.98-.97 1.21C7.85 18.75 7 20.24 7 22"),
            IconNode.PathData("M14 14.66V17c0 .55.47.98.97 1.21C16.15 18.75 17 20.24 17 22"),
            IconNode.PathData("M18 2H6v7a6 6 0 0 0 12 0V2Z"),
        ),
    ),
    Upload(
        listOf(
            IconNode.PathData("M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"),
            IconNode.Polyline("17 8 12 3 7 8"),
            IconNode.Line(12f, 3f, 12f, 15f),
        ),
    ),
    UploadCloud(
        listOf(
            IconNode.PathData("M12 13v8"),
            IconNode.PathData("M4 14.899A7 7 0 1 1 15.71 8h1.79a4.5 4.5 0 0 1 2.5 8.242"),
            IconNode.PathData("m8 17 4-4 4 4"),
        ),
    ),
    UserRound(
        listOf(
            IconNode.Circle(12f, 8f, 5f),
            IconNode.PathData("M20 21a8 8 0 0 0-16 0"),
        ),
    ),
    Users(
        listOf(
            IconNode.PathData("M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2"),
            IconNode.Circle(9f, 7f, 4f),
            IconNode.PathData("M22 21v-2a4 4 0 0 0-3-3.87"),
            IconNode.PathData("M16 3.13a4 4 0 0 1 0 7.75"),
        ),
    ),
    Volume1(
        listOf(
            IconNode.PathData("M11 4.702a.705.705 0 0 0-1.203-.498L6.413 7.587A1.4 1.4 0 0 1 5.416 8H3a1 1 0 0 0-1 1v6a1 1 0 0 0 1 1h2.416a1.4 1.4 0 0 1 .997.413l3.383 3.384A.705.705 0 0 0 11 19.298z"),
            IconNode.PathData("M16 9a5 5 0 0 1 0 6"),
        ),
    ),
    Volume2(
        listOf(
            IconNode.PathData("M11 4.702a.705.705 0 0 0-1.203-.498L6.413 7.587A1.4 1.4 0 0 1 5.416 8H3a1 1 0 0 0-1 1v6a1 1 0 0 0 1 1h2.416a1.4 1.4 0 0 1 .997.413l3.383 3.384A.705.705 0 0 0 11 19.298z"),
            IconNode.PathData("M16 9a5 5 0 0 1 0 6"),
            IconNode.PathData("M19.364 18.364a9 9 0 0 0 0-12.728"),
        ),
    ),
    VolumeX(
        listOf(
            IconNode.PathData("M11 4.702a.705.705 0 0 0-1.203-.498L6.413 7.587A1.4 1.4 0 0 1 5.416 8H3a1 1 0 0 0-1 1v6a1 1 0 0 0 1 1h2.416a1.4 1.4 0 0 1 .997.413l3.383 3.384A.705.705 0 0 0 11 19.298z"),
            IconNode.Line(22f, 9f, 16f, 15f),
            IconNode.Line(16f, 9f, 22f, 15f),
        ),
    ),
    X(
        listOf(
            IconNode.PathData("M18 6 6 18"),
            IconNode.PathData("m6 6 12 12"),
        ),
    ),
    Download(
        listOf(
            IconNode.PathData("M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"),
            IconNode.Polyline("7 10 12 15 17 10"),
            IconNode.Line(12f, 15f, 12f, 3f),
        ),
    ),
    Archive(
        listOf(
            IconNode.Rect(2f, 3f, 20f, 5f, 1f),
            IconNode.PathData("M4 8v11a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8"),
            IconNode.PathData("M10 12h4"),
        ),
    ),
    RefreshCw(
        listOf(
            IconNode.PathData("M3 12a9 9 0 0 1 9-9 9.75 9.75 0 0 1 6.74 2.74L21 8"),
            IconNode.PathData("M21 3v5h-5"),
            IconNode.PathData("M21 12a9 9 0 0 1-9 9 9.75 9.75 0 0 1-6.74-2.74L3 16"),
            IconNode.PathData("M8 16H3v5"),
        ),
    ),
    Settings(
        listOf(
            IconNode.PathData("M12.22 2h-.44a2 2 0 0 0-2 2v.18a2 2 0 0 1-1 1.73l-.43.25a2 2 0 0 1-2 0l-.15-.08a2 2 0 0 0-2.73.73l-.22.38a2 2 0 0 0 .73 2.73l.15.1a2 2 0 0 1 1 1.72v.51a2 2 0 0 1-1 1.74l-.15.09a2 2 0 0 0-.73 2.73l.22.38a2 2 0 0 0 2.73.73l.15-.08a2 2 0 0 1 2 0l.43.25a2 2 0 0 1 1 1.73V20a2 2 0 0 0 2 2h.44a2 2 0 0 0 2-2v-.18a2 2 0 0 1 1-1.73l.43-.25a2 2 0 0 1 2 0l.15.08a2 2 0 0 0 2.73-.73l.22-.39a2 2 0 0 0-.73-2.73l-.15-.08a2 2 0 0 1-1-1.74v-.5a2 2 0 0 1 1-1.74l.15-.09a2 2 0 0 0 .73-2.73l-.22-.38a2 2 0 0 0-2.73-.73l-.15.08a2 2 0 0 1-2 0l-.43-.25a2 2 0 0 1-1-1.73V4a2 2 0 0 0-2-2z"),
            IconNode.Circle(12f, 12f, 3f),
        ),
    ),
    Info(
        listOf(
            IconNode.Circle(12f, 12f, 10f),
            IconNode.PathData("M12 16v-4"),
            IconNode.PathData("M12 8h.01"),
        ),
    ),
    Disc3(
        listOf(
            IconNode.Circle(12f, 12f, 10f),
            IconNode.PathData("M6 12c0-1.7.7-3.2 1.8-4.2"),
            IconNode.Circle(12f, 12f, 2f),
            IconNode.PathData("M18 12c0 1.7-.7 3.2-1.8 4.2"),
        ),
    ),
    ListPlus(
        listOf(
            IconNode.PathData("M11 12H3"),
            IconNode.PathData("M16 6H3"),
            IconNode.PathData("M16 18H3"),
            IconNode.PathData("M18 9v6"),
            IconNode.PathData("M21 12h-6"),
        ),
    ),
    CircleCheck(
        listOf(
            IconNode.Circle(12f, 12f, 10f),
            IconNode.PathData("m9 12 2 2 4-4"),
        ),
    ),
    Cloud(
        listOf(
            IconNode.PathData("M17.5 19H9a7 7 0 1 1 6.71-9h1.79a4.5 4.5 0 1 1 0 9Z"),
        ),
    ),
    Smartphone(
        listOf(
            IconNode.Rect(5f, 2f, 14f, 20f, 2f),
            IconNode.PathData("M12 18h.01"),
        ),
    ),
    Folder(
        listOf(
            IconNode.PathData("M20 20a2 2 0 0 0 2-2V8a2 2 0 0 0-2-2h-7.9a2 2 0 0 1-1.69-.9L9.6 3.9A2 2 0 0 0 7.93 3H4a2 2 0 0 0-2 2v13a2 2 0 0 0 2 2Z"),
        ),
    ),
    FileMusic(
        listOf(
            IconNode.Circle(14f, 16f, 2f),
            IconNode.Circle(6f, 18f, 2f),
            IconNode.PathData("M4 12.4V4a2 2 0 0 1 2-2h8.5L20 7.5V20a2 2 0 0 1-2 2h-7.5"),
            IconNode.PathData("M8 18v-7.7L16 9v7"),
        ),
    ),
    Library(
        listOf(
            IconNode.PathData("m16 6 4 14"),
            IconNode.PathData("M12 6v14"),
            IconNode.PathData("M8 8v12"),
            IconNode.PathData("M4 4v16"),
        ),
    ),
    Radio(
        listOf(
            IconNode.PathData("M4.9 19.1C1 15.2 1 8.8 4.9 4.9"),
            IconNode.PathData("M7.8 16.2c-2.3-2.3-2.3-6.1 0-8.5"),
            IconNode.Circle(12f, 12f, 2f),
            IconNode.PathData("M16.2 7.8c2.3 2.3 2.3 6.1 0 8.5"),
            IconNode.PathData("M19.1 4.9C23 8.8 23 15.1 19.1 19"),
        ),
    ),
    Wifi(
        listOf(
            IconNode.PathData("M12 20h.01"),
            IconNode.PathData("M2 8.82a15 15 0 0 1 20 0"),
            IconNode.PathData("M5 12.859a10 10 0 0 1 14 0"),
            IconNode.PathData("M8.5 16.429a5 5 0 0 1 7 0"),
        ),
    ),
    Share(
        listOf(
            IconNode.PathData("M4 12v8a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2v-8"),
            IconNode.Polyline("16 6 12 2 8 6"),
            IconNode.Line(12f, 2f, 12f, 15f),
        ),
    ),
    Clock(
        listOf(
            IconNode.Circle(12f, 12f, 10f),
            IconNode.Polyline("12 6 12 12 16 14"),
        ),
    ),
    CheckCheck(
        listOf(
            IconNode.PathData("M18 6 7 17l-5-5"),
            IconNode.PathData("m22 10-7.5 7.5L13 16"),
        ),
    ),
    TriangleAlert(
        listOf(
            IconNode.PathData("m21.73 18-8-14a2 2 0 0 0-3.48 0l-8 14A2 2 0 0 0 4 21h16a2 2 0 0 0 1.73-3"),
            IconNode.PathData("M12 9v4"),
            IconNode.PathData("M12 17h.01"),
        ),
    ),
    SlidersHorizontal(
        listOf(
            IconNode.Line(21f, 4f, 14f, 4f),
            IconNode.Line(10f, 4f, 3f, 4f),
            IconNode.Line(21f, 12f, 12f, 12f),
            IconNode.Line(8f, 12f, 3f, 12f),
            IconNode.Line(21f, 20f, 16f, 20f),
            IconNode.Line(12f, 20f, 3f, 20f),
            IconNode.Line(14f, 2f, 14f, 6f),
            IconNode.Line(8f, 10f, 8f, 14f),
            IconNode.Line(16f, 18f, 16f, 22f),
        ),
    ),
    Monitor(
        listOf(
            IconNode.Rect(2f, 3f, 20f, 14f, 2f),
            IconNode.Line(8f, 21f, 16f, 21f),
            IconNode.Line(12f, 17f, 12f, 21f),
        ),
    ),
    TabletSmartphone(
        listOf(
            IconNode.Rect(3f, 8f, 10f, 14f, 2f),
            IconNode.PathData("M5 4a2 2 0 0 1 2-2h12a2 2 0 0 1 2 2v16a2 2 0 0 1-2 2h-2.4"),
            IconNode.PathData("M8 18h.01"),
        ),
    );
}
