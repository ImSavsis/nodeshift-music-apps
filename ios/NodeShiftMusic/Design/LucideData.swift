import Foundation

enum IconNode: Sendable {
    case path(String)
    case circle(cx: Double, cy: Double, r: Double)
    case line(x1: Double, y1: Double, x2: Double, y2: Double)
    case polyline(String)
    case polygon(String)
    case rect(x: Double, y: Double, width: Double, height: Double, rx: Double)
}

enum LucideName: String, CaseIterable, Sendable {
    case arrowDownToLine
    case bookmark
    case calendar
    case camera
    case check
    case chevronDown
    case chevronUp
    case chevronRight
    case chevronLeft
    case circleAlert
    case clapperboard
    case cloudDownload
    case copy
    case ellipsis
    case externalLink
    case fileText
    case folderUp
    case hardDrive
    case heart
    case imagePlus
    case keyboard
    case layoutGrid
    case layoutList
    case link
    case listEnd
    case listMusic
    case listStart
    case logIn
    case logOut
    case maximize2
    case micOff
    case music2
    case pause
    case pencil
    case play
    case plus
    case repeatAll
    case repeat1
    case search
    case shuffle
    case skipBack
    case skipForward
    case sparkles
    case trash2
    case trophy
    case upload
    case uploadCloud
    case userRound
    case users
    case volume1
    case volume2
    case volumeX
    case x
    case download
    case archive
    case refreshCw
    case settings
    case info
    case disc3
    case listPlus
    case circleCheck
    case cloud
    case smartphone
    case folder
    case fileMusic
    case library
    case radio
    case wifi
    case share
    case clock
    case checkCheck
    case triangleAlert
    case slidersHorizontal
    case monitor
    case tabletSmartphone

    var nodes: [IconNode] {
        switch self {
        case .arrowDownToLine:
            return [
                .path("M12 17V3"),
                .path("m6 11 6 6 6-6"),
                .path("M19 21H5"),
            ]
        case .bookmark:
            return [
                .path("m19 21-7-4-7 4V5a2 2 0 0 1 2-2h10a2 2 0 0 1 2 2v16z"),
            ]
        case .calendar:
            return [
                .path("M8 2v4"),
                .path("M16 2v4"),
                .rect(x: 3, y: 4, width: 18, height: 18, rx: 2),
                .path("M3 10h18"),
            ]
        case .camera:
            return [
                .path("M14.5 4h-5L7 7H4a2 2 0 0 0-2 2v9a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2V9a2 2 0 0 0-2-2h-3l-2.5-3z"),
                .circle(cx: 12, cy: 13, r: 3),
            ]
        case .check:
            return [
                .path("M20 6 9 17l-5-5"),
            ]
        case .chevronDown:
            return [
                .path("m6 9 6 6 6-6"),
            ]
        case .chevronUp:
            return [
                .path("m18 15-6-6-6 6"),
            ]
        case .chevronRight:
            return [
                .path("m9 18 6-6-6-6"),
            ]
        case .chevronLeft:
            return [
                .path("m15 18-6-6 6-6"),
            ]
        case .circleAlert:
            return [
                .circle(cx: 12, cy: 12, r: 10),
                .line(x1: 12, y1: 8, x2: 12, y2: 12),
                .line(x1: 12, y1: 16, x2: 12.01, y2: 16),
            ]
        case .clapperboard:
            return [
                .path("M20.2 6 3 11l-.9-2.4c-.3-1.1.3-2.2 1.3-2.5l13.5-4c1.1-.3 2.2.3 2.5 1.3Z"),
                .path("m6.2 5.3 3.1 3.9"),
                .path("m12.4 3.4 3.1 4"),
                .path("M3 11h18v8a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2Z"),
            ]
        case .cloudDownload:
            return [
                .path("M12 13v8l-4-4"),
                .path("m12 21 4-4"),
                .path("M4.393 15.269A7 7 0 1 1 15.71 8h1.79a4.5 4.5 0 0 1 2.436 8.284"),
            ]
        case .copy:
            return [
                .rect(x: 8, y: 8, width: 14, height: 14, rx: 2),
                .path("M4 16c-1.1 0-2-.9-2-2V4c0-1.1.9-2 2-2h10c1.1 0 2 .9 2 2"),
            ]
        case .ellipsis:
            return [
                .circle(cx: 12, cy: 12, r: 1),
                .circle(cx: 19, cy: 12, r: 1),
                .circle(cx: 5, cy: 12, r: 1),
            ]
        case .externalLink:
            return [
                .path("M15 3h6v6"),
                .path("M10 14 21 3"),
                .path("M18 13v6a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h6"),
            ]
        case .fileText:
            return [
                .path("M15 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V7Z"),
                .path("M14 2v4a2 2 0 0 0 2 2h4"),
                .path("M10 9H8"),
                .path("M16 13H8"),
                .path("M16 17H8"),
            ]
        case .folderUp:
            return [
                .path("M20 20a2 2 0 0 0 2-2V8a2 2 0 0 0-2-2h-7.9a2 2 0 0 1-1.69-.9L9.6 3.9A2 2 0 0 0 7.93 3H4a2 2 0 0 0-2 2v13a2 2 0 0 0 2 2Z"),
                .path("M12 10v6"),
                .path("m9 13 3-3 3 3"),
            ]
        case .hardDrive:
            return [
                .line(x1: 22, y1: 12, x2: 2, y2: 12),
                .path("M5.45 5.11 2 12v6a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2v-6l-3.45-6.89A2 2 0 0 0 16.76 4H7.24a2 2 0 0 0-1.79 1.11z"),
                .line(x1: 6, y1: 16, x2: 6.01, y2: 16),
                .line(x1: 10, y1: 16, x2: 10.01, y2: 16),
            ]
        case .heart:
            return [
                .path("M19 14c1.49-1.46 3-3.21 3-5.5A5.5 5.5 0 0 0 16.5 3c-1.76 0-3 .5-4.5 2-1.5-1.5-2.74-2-4.5-2A5.5 5.5 0 0 0 2 8.5c0 2.3 1.5 4.05 3 5.5l7 7Z"),
            ]
        case .imagePlus:
            return [
                .path("M16 5h6"),
                .path("M19 2v6"),
                .path("M21 11.5V19a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h7.5"),
                .path("m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"),
                .circle(cx: 9, cy: 9, r: 2),
            ]
        case .keyboard:
            return [
                .path("M10 8h.01"),
                .path("M12 12h.01"),
                .path("M14 8h.01"),
                .path("M16 12h.01"),
                .path("M18 8h.01"),
                .path("M6 8h.01"),
                .path("M7 16h10"),
                .path("M8 12h.01"),
                .rect(x: 2, y: 4, width: 20, height: 16, rx: 2),
            ]
        case .layoutGrid:
            return [
                .rect(x: 3, y: 3, width: 7, height: 7, rx: 1),
                .rect(x: 14, y: 3, width: 7, height: 7, rx: 1),
                .rect(x: 14, y: 14, width: 7, height: 7, rx: 1),
                .rect(x: 3, y: 14, width: 7, height: 7, rx: 1),
            ]
        case .layoutList:
            return [
                .rect(x: 3, y: 3, width: 7, height: 7, rx: 1),
                .rect(x: 3, y: 14, width: 7, height: 7, rx: 1),
                .path("M14 4h7"),
                .path("M14 9h7"),
                .path("M14 15h7"),
                .path("M14 20h7"),
            ]
        case .link:
            return [
                .path("M10 13a5 5 0 0 0 7.54.54l3-3a5 5 0 0 0-7.07-7.07l-1.72 1.71"),
                .path("M14 11a5 5 0 0 0-7.54-.54l-3 3a5 5 0 0 0 7.07 7.07l1.71-1.71"),
            ]
        case .listEnd:
            return [
                .path("M16 12H3"),
                .path("M16 6H3"),
                .path("M10 18H3"),
                .path("M21 6v10a2 2 0 0 1-2 2h-5"),
                .path("m16 16-2 2 2 2"),
            ]
        case .listMusic:
            return [
                .path("M21 15V6"),
                .path("M18.5 18a2.5 2.5 0 1 0 0-5 2.5 2.5 0 0 0 0 5Z"),
                .path("M12 12H3"),
                .path("M16 6H3"),
                .path("M12 18H3"),
            ]
        case .listStart:
            return [
                .path("M16 12H3"),
                .path("M16 18H3"),
                .path("M10 6H3"),
                .path("M21 18V8a2 2 0 0 0-2-2h-5"),
                .path("m16 8-2-2 2-2"),
            ]
        case .logIn:
            return [
                .path("M15 3h4a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2h-4"),
                .polyline("10 17 15 12 10 7"),
                .line(x1: 15, y1: 12, x2: 3, y2: 12),
            ]
        case .logOut:
            return [
                .path("M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4"),
                .polyline("16 17 21 12 16 7"),
                .line(x1: 21, y1: 12, x2: 9, y2: 12),
            ]
        case .maximize2:
            return [
                .polyline("15 3 21 3 21 9"),
                .polyline("9 21 3 21 3 15"),
                .line(x1: 21, y1: 3, x2: 14, y2: 10),
                .line(x1: 3, y1: 21, x2: 10, y2: 14),
            ]
        case .micOff:
            return [
                .line(x1: 2, y1: 2, x2: 22, y2: 22),
                .path("M18.89 13.23A7.12 7.12 0 0 0 19 12v-2"),
                .path("M5 10v2a7 7 0 0 0 12 5"),
                .path("M15 9.34V5a3 3 0 0 0-5.68-1.33"),
                .path("M9 9v3a3 3 0 0 0 5.12 2.12"),
                .line(x1: 12, y1: 19, x2: 12, y2: 22),
            ]
        case .music2:
            return [
                .circle(cx: 8, cy: 18, r: 4),
                .path("M12 18V2l7 4"),
            ]
        case .pause:
            return [
                .rect(x: 14, y: 4, width: 4, height: 16, rx: 1),
                .rect(x: 6, y: 4, width: 4, height: 16, rx: 1),
            ]
        case .pencil:
            return [
                .path("M21.174 6.812a1 1 0 0 0-3.986-3.987L3.842 16.174a2 2 0 0 0-.5.83l-1.321 4.352a.5.5 0 0 0 .623.622l4.353-1.32a2 2 0 0 0 .83-.497z"),
                .path("m15 5 4 4"),
            ]
        case .play:
            return [
                .polygon("6 3 20 12 6 21 6 3"),
            ]
        case .plus:
            return [
                .path("M5 12h14"),
                .path("M12 5v14"),
            ]
        case .repeatAll:
            return [
                .path("m17 2 4 4-4 4"),
                .path("M3 11v-1a4 4 0 0 1 4-4h14"),
                .path("m7 22-4-4 4-4"),
                .path("M21 13v1a4 4 0 0 1-4 4H3"),
            ]
        case .repeat1:
            return [
                .path("m17 2 4 4-4 4"),
                .path("M3 11v-1a4 4 0 0 1 4-4h14"),
                .path("m7 22-4-4 4-4"),
                .path("M21 13v1a4 4 0 0 1-4 4H3"),
                .path("M11 10h1v4"),
            ]
        case .search:
            return [
                .circle(cx: 11, cy: 11, r: 8),
                .path("m21 21-4.3-4.3"),
            ]
        case .shuffle:
            return [
                .path("M2 18h1.4c1.3 0 2.5-.6 3.3-1.7l6.1-8.6c.7-1.1 2-1.7 3.3-1.7H22"),
                .path("m18 2 4 4-4 4"),
                .path("M2 6h1.9c1.5 0 2.9.9 3.6 2.2"),
                .path("M22 18h-5.9c-1.3 0-2.6-.7-3.3-1.8l-.5-.8"),
                .path("m18 14 4 4-4 4"),
            ]
        case .skipBack:
            return [
                .polygon("19 20 9 12 19 4 19 20"),
                .line(x1: 5, y1: 19, x2: 5, y2: 5),
            ]
        case .skipForward:
            return [
                .polygon("5 4 15 12 5 20 5 4"),
                .line(x1: 19, y1: 5, x2: 19, y2: 19),
            ]
        case .sparkles:
            return [
                .path("M9.937 15.5A2 2 0 0 0 8.5 14.063l-6.135-1.582a.5.5 0 0 1 0-.962L8.5 9.936A2 2 0 0 0 9.937 8.5l1.582-6.135a.5.5 0 0 1 .963 0L14.063 8.5A2 2 0 0 0 15.5 9.937l6.135 1.581a.5.5 0 0 1 0 .964L15.5 14.063a2 2 0 0 0-1.437 1.437l-1.582 6.135a.5.5 0 0 1-.963 0z"),
                .path("M20 3v4"),
                .path("M22 5h-4"),
                .path("M4 17v2"),
                .path("M5 18H3"),
            ]
        case .trash2:
            return [
                .path("M3 6h18"),
                .path("M19 6v14c0 1-1 2-2 2H7c-1 0-2-1-2-2V6"),
                .path("M8 6V4c0-1 1-2 2-2h4c1 0 2 1 2 2v2"),
                .line(x1: 10, y1: 11, x2: 10, y2: 17),
                .line(x1: 14, y1: 11, x2: 14, y2: 17),
            ]
        case .trophy:
            return [
                .path("M6 9H4.5a2.5 2.5 0 0 1 0-5H6"),
                .path("M18 9h1.5a2.5 2.5 0 0 0 0-5H18"),
                .path("M4 22h16"),
                .path("M10 14.66V17c0 .55-.47.98-.97 1.21C7.85 18.75 7 20.24 7 22"),
                .path("M14 14.66V17c0 .55.47.98.97 1.21C16.15 18.75 17 20.24 17 22"),
                .path("M18 2H6v7a6 6 0 0 0 12 0V2Z"),
            ]
        case .upload:
            return [
                .path("M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"),
                .polyline("17 8 12 3 7 8"),
                .line(x1: 12, y1: 3, x2: 12, y2: 15),
            ]
        case .uploadCloud:
            return [
                .path("M12 13v8"),
                .path("M4 14.899A7 7 0 1 1 15.71 8h1.79a4.5 4.5 0 0 1 2.5 8.242"),
                .path("m8 17 4-4 4 4"),
            ]
        case .userRound:
            return [
                .circle(cx: 12, cy: 8, r: 5),
                .path("M20 21a8 8 0 0 0-16 0"),
            ]
        case .users:
            return [
                .path("M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2"),
                .circle(cx: 9, cy: 7, r: 4),
                .path("M22 21v-2a4 4 0 0 0-3-3.87"),
                .path("M16 3.13a4 4 0 0 1 0 7.75"),
            ]
        case .volume1:
            return [
                .path("M11 4.702a.705.705 0 0 0-1.203-.498L6.413 7.587A1.4 1.4 0 0 1 5.416 8H3a1 1 0 0 0-1 1v6a1 1 0 0 0 1 1h2.416a1.4 1.4 0 0 1 .997.413l3.383 3.384A.705.705 0 0 0 11 19.298z"),
                .path("M16 9a5 5 0 0 1 0 6"),
            ]
        case .volume2:
            return [
                .path("M11 4.702a.705.705 0 0 0-1.203-.498L6.413 7.587A1.4 1.4 0 0 1 5.416 8H3a1 1 0 0 0-1 1v6a1 1 0 0 0 1 1h2.416a1.4 1.4 0 0 1 .997.413l3.383 3.384A.705.705 0 0 0 11 19.298z"),
                .path("M16 9a5 5 0 0 1 0 6"),
                .path("M19.364 18.364a9 9 0 0 0 0-12.728"),
            ]
        case .volumeX:
            return [
                .path("M11 4.702a.705.705 0 0 0-1.203-.498L6.413 7.587A1.4 1.4 0 0 1 5.416 8H3a1 1 0 0 0-1 1v6a1 1 0 0 0 1 1h2.416a1.4 1.4 0 0 1 .997.413l3.383 3.384A.705.705 0 0 0 11 19.298z"),
                .line(x1: 22, y1: 9, x2: 16, y2: 15),
                .line(x1: 16, y1: 9, x2: 22, y2: 15),
            ]
        case .x:
            return [
                .path("M18 6 6 18"),
                .path("m6 6 12 12"),
            ]
        case .download:
            return [
                .path("M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"),
                .polyline("7 10 12 15 17 10"),
                .line(x1: 12, y1: 15, x2: 12, y2: 3),
            ]
        case .archive:
            return [
                .rect(x: 2, y: 3, width: 20, height: 5, rx: 1),
                .path("M4 8v11a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8"),
                .path("M10 12h4"),
            ]
        case .refreshCw:
            return [
                .path("M3 12a9 9 0 0 1 9-9 9.75 9.75 0 0 1 6.74 2.74L21 8"),
                .path("M21 3v5h-5"),
                .path("M21 12a9 9 0 0 1-9 9 9.75 9.75 0 0 1-6.74-2.74L3 16"),
                .path("M8 16H3v5"),
            ]
        case .settings:
            return [
                .path("M12.22 2h-.44a2 2 0 0 0-2 2v.18a2 2 0 0 1-1 1.73l-.43.25a2 2 0 0 1-2 0l-.15-.08a2 2 0 0 0-2.73.73l-.22.38a2 2 0 0 0 .73 2.73l.15.1a2 2 0 0 1 1 1.72v.51a2 2 0 0 1-1 1.74l-.15.09a2 2 0 0 0-.73 2.73l.22.38a2 2 0 0 0 2.73.73l.15-.08a2 2 0 0 1 2 0l.43.25a2 2 0 0 1 1 1.73V20a2 2 0 0 0 2 2h.44a2 2 0 0 0 2-2v-.18a2 2 0 0 1 1-1.73l.43-.25a2 2 0 0 1 2 0l.15.08a2 2 0 0 0 2.73-.73l.22-.39a2 2 0 0 0-.73-2.73l-.15-.08a2 2 0 0 1-1-1.74v-.5a2 2 0 0 1 1-1.74l.15-.09a2 2 0 0 0 .73-2.73l-.22-.38a2 2 0 0 0-2.73-.73l-.15.08a2 2 0 0 1-2 0l-.43-.25a2 2 0 0 1-1-1.73V4a2 2 0 0 0-2-2z"),
                .circle(cx: 12, cy: 12, r: 3),
            ]
        case .info:
            return [
                .circle(cx: 12, cy: 12, r: 10),
                .path("M12 16v-4"),
                .path("M12 8h.01"),
            ]
        case .disc3:
            return [
                .circle(cx: 12, cy: 12, r: 10),
                .path("M6 12c0-1.7.7-3.2 1.8-4.2"),
                .circle(cx: 12, cy: 12, r: 2),
                .path("M18 12c0 1.7-.7 3.2-1.8 4.2"),
            ]
        case .listPlus:
            return [
                .path("M11 12H3"),
                .path("M16 6H3"),
                .path("M16 18H3"),
                .path("M18 9v6"),
                .path("M21 12h-6"),
            ]
        case .circleCheck:
            return [
                .circle(cx: 12, cy: 12, r: 10),
                .path("m9 12 2 2 4-4"),
            ]
        case .cloud:
            return [
                .path("M17.5 19H9a7 7 0 1 1 6.71-9h1.79a4.5 4.5 0 1 1 0 9Z"),
            ]
        case .smartphone:
            return [
                .rect(x: 5, y: 2, width: 14, height: 20, rx: 2),
                .path("M12 18h.01"),
            ]
        case .folder:
            return [
                .path("M20 20a2 2 0 0 0 2-2V8a2 2 0 0 0-2-2h-7.9a2 2 0 0 1-1.69-.9L9.6 3.9A2 2 0 0 0 7.93 3H4a2 2 0 0 0-2 2v13a2 2 0 0 0 2 2Z"),
            ]
        case .fileMusic:
            return [
                .circle(cx: 14, cy: 16, r: 2),
                .circle(cx: 6, cy: 18, r: 2),
                .path("M4 12.4V4a2 2 0 0 1 2-2h8.5L20 7.5V20a2 2 0 0 1-2 2h-7.5"),
                .path("M8 18v-7.7L16 9v7"),
            ]
        case .library:
            return [
                .path("m16 6 4 14"),
                .path("M12 6v14"),
                .path("M8 8v12"),
                .path("M4 4v16"),
            ]
        case .radio:
            return [
                .path("M4.9 19.1C1 15.2 1 8.8 4.9 4.9"),
                .path("M7.8 16.2c-2.3-2.3-2.3-6.1 0-8.5"),
                .circle(cx: 12, cy: 12, r: 2),
                .path("M16.2 7.8c2.3 2.3 2.3 6.1 0 8.5"),
                .path("M19.1 4.9C23 8.8 23 15.1 19.1 19"),
            ]
        case .wifi:
            return [
                .path("M12 20h.01"),
                .path("M2 8.82a15 15 0 0 1 20 0"),
                .path("M5 12.859a10 10 0 0 1 14 0"),
                .path("M8.5 16.429a5 5 0 0 1 7 0"),
            ]
        case .share:
            return [
                .path("M4 12v8a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2v-8"),
                .polyline("16 6 12 2 8 6"),
                .line(x1: 12, y1: 2, x2: 12, y2: 15),
            ]
        case .clock:
            return [
                .circle(cx: 12, cy: 12, r: 10),
                .polyline("12 6 12 12 16 14"),
            ]
        case .checkCheck:
            return [
                .path("M18 6 7 17l-5-5"),
                .path("m22 10-7.5 7.5L13 16"),
            ]
        case .triangleAlert:
            return [
                .path("m21.73 18-8-14a2 2 0 0 0-3.48 0l-8 14A2 2 0 0 0 4 21h16a2 2 0 0 0 1.73-3"),
                .path("M12 9v4"),
                .path("M12 17h.01"),
            ]
        case .slidersHorizontal:
            return [
                .line(x1: 21, y1: 4, x2: 14, y2: 4),
                .line(x1: 10, y1: 4, x2: 3, y2: 4),
                .line(x1: 21, y1: 12, x2: 12, y2: 12),
                .line(x1: 8, y1: 12, x2: 3, y2: 12),
                .line(x1: 21, y1: 20, x2: 16, y2: 20),
                .line(x1: 12, y1: 20, x2: 3, y2: 20),
                .line(x1: 14, y1: 2, x2: 14, y2: 6),
                .line(x1: 8, y1: 10, x2: 8, y2: 14),
                .line(x1: 16, y1: 18, x2: 16, y2: 22),
            ]
        case .monitor:
            return [
                .rect(x: 2, y: 3, width: 20, height: 14, rx: 2),
                .line(x1: 8, y1: 21, x2: 16, y2: 21),
                .line(x1: 12, y1: 17, x2: 12, y2: 21),
            ]
        case .tabletSmartphone:
            return [
                .rect(x: 3, y: 8, width: 10, height: 14, rx: 2),
                .path("M5 4a2 2 0 0 1 2-2h12a2 2 0 0 1 2 2v16a2 2 0 0 1-2 2h-2.4"),
                .path("M8 18h.01"),
            ]
        }
    }
}
