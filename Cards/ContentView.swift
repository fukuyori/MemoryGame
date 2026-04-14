//
//  ContentView.swift
//  Cards
//
//  Created by 福寄典明 on 2026/04/14.
//

import SwiftUI
import Combine

#if canImport(UIKit)
import UIKit
private typealias PlatformImage = UIImage
#elseif canImport(AppKit)
import AppKit
private typealias PlatformImage = NSImage
#endif

struct ContentView: View {
    @AppStorage("gameHistoryV2") private var gameHistoryData = ""
    @AppStorage("selectedCardBackStyle") private var selectedCardBackStyleRawValue = ""
    @AppStorage("selectedDifficulty") private var selectedDifficultyRawValue = GameDifficulty.intermediate.rawValue
    @State private var difficulty: GameDifficulty
    @State private var cards: [GameCard]
    @State private var selectedIndices: [Int] = []
    @State private var recentlyMatchedIndices: Set<Int> = []
    @State private var isResolvingTurn = false
    @State private var moves = 0
    @State private var gameStartDate = Date()
    @State private var elapsedTime: TimeInterval = 0
    @State private var hasRecordedCurrentGame = false
    @State private var currentPage = 0
    @State private var isShowingBackStylePicker = false

    init() {
        let savedDifficulty = GameDifficulty(rawValue: UserDefaults.standard.string(forKey: "selectedDifficulty") ?? "") ?? .intermediate
        _difficulty = State(initialValue: savedDifficulty)
        _cards = State(initialValue: GameCard.makeDeck(pairCount: savedDifficulty.pairCount))
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.08, green: 0.15, blue: 0.32), Color(red: 0.04, green: 0.36, blue: 0.46)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            TabView(selection: $currentPage) {
                GeometryReader { geometry in
                    let layout = gameLayout(in: geometry.size)

                    VStack(spacing: 8) {
                        VStack(spacing: 2) {
                            StatusSummaryView(
                                movesText: movesText,
                                timeText: timeText,
                                progressText: progressText,
                                isCompleted: matchedCount == cards.count
                            )
                        }

                        Picker("難易度", selection: $difficulty) {
                            ForEach(GameDifficulty.allCases) { level in
                                Text(level.title).tag(level)
                            }
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: difficulty) { _, newValue in
                            selectedDifficultyRawValue = newValue.rawValue
                            resetGame(for: newValue)
                        }

                        LazyVGrid(columns: layout.columns, spacing: layout.spacing) {
                            ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                                Button {
                                    flipCard(at: index)
                                } label: {
                                    MemoryCardView(
                                        card: card,
                                        height: layout.cardHeight,
                                        isHighlighted: recentlyMatchedIndices.contains(index),
                                        backStyle: selectedBackStyle
                                    )
                                }
                                .buttonStyle(.plain)
                                .allowsHitTesting(!(card.isFaceUp || card.isMatched || isResolvingTurn))
                            }
                        }

                        Button("もう一度遊ぶ") {
                            resetGame()
                        }
                        .font(.headline)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(.white.opacity(0.18))
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
                .tag(0)

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("履歴")
                                .font(.headline.bold())
                                .foregroundStyle(.white)

                            Spacer()

                            Button("全履歴削除") {
                                clearHistory()
                            }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.92))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.red.opacity(0.28))
                            .clipShape(Capsule())

                            Text("右へスワイプで戻る")
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.7))
                        }

                        ScoreSummaryView(stats: gameStatistics)
                        ScoreHistoryView(history: recentHistory)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .tag(1)
            }
            #if os(iOS)
            .tabViewStyle(.page(indexDisplayMode: .automatic))
            #endif

            if shouldShowBackStylePicker {
                CardBackPickerOverlay(
                    selectedStyle: selectedBackStyle,
                    onSelect: { style in
                        selectedCardBackStyleRawValue = style.rawValue
                        isShowingBackStylePicker = false
                        resetGame()
                    }
                )
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: shouldShowBackStylePicker)
        .onReceive(Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()) { now in
            guard !hasRecordedCurrentGame else { return }
            elapsedTime = now.timeIntervalSince(gameStartDate)
        }
    }

    private var matchedCount: Int {
        cards.filter(\.isMatched).count
    }

    private var movesText: String {
        matchedCount == cards.count ? "クリア！ \(moves) 手" : "\(moves) 手"
    }

    private var timeText: String {
        formattedDuration(elapsedTime)
    }

    private var progressText: String {
        "\(matchedCount / 2) / \(cards.count / 2) ペア"
    }

    private var gameHistory: [GameResult] {
        guard let data = gameHistoryData.data(using: .utf8),
              let history = try? JSONDecoder().decode([GameResult].self, from: data) else {
            return []
        }

        return history
    }

    private var gameStatistics: GameStatistics {
        GameStatistics(history: gameHistory)
    }

    private var recentHistory: [GameResult] {
        Array(gameHistory.prefix(10))
    }

    private var selectedBackStyle: CardBackStyle {
        CardBackStyle(rawValue: selectedCardBackStyleRawValue) ?? .mondrian
    }

    private var shouldShowBackStylePicker: Bool {
        selectedCardBackStyleRawValue.isEmpty || isShowingBackStylePicker
    }

    private func flipCard(at index: Int) {
        guard !cards[index].isFaceUp, !cards[index].isMatched, selectedIndices.count < 2 else {
            return
        }

        cards[index].isFaceUp = true
        selectedIndices.append(index)

        guard selectedIndices.count == 2 else { return }

        moves += 1
        isResolvingTurn = true

        let firstIndex = selectedIndices[0]
        let secondIndex = selectedIndices[1]

        if cards[firstIndex].assetName == cards[secondIndex].assetName {
            cards[firstIndex].isMatched = true
            cards[secondIndex].isMatched = true
            recentlyMatchedIndices = [firstIndex, secondIndex]
            selectedIndices.removeAll()
            isResolvingTurn = false

            if cards.allSatisfy(\.isMatched) {
                recordGameIfNeeded()
            }

            Task {
                try? await Task.sleep(for: .seconds(0.45))
                recentlyMatchedIndices.subtract([firstIndex, secondIndex])
            }
        } else {
            Task {
                try? await Task.sleep(for: .seconds(0.9))
                cards[firstIndex].isFaceUp = false
                cards[secondIndex].isFaceUp = false
                selectedIndices.removeAll()
                isResolvingTurn = false
            }
        }
    }

    private func resetGame() {
        resetGame(for: difficulty)
    }

    private func resetGame(for difficulty: GameDifficulty) {
        cards = GameCard.makeDeck(pairCount: difficulty.pairCount)
        selectedIndices.removeAll()
        recentlyMatchedIndices.removeAll()
        isResolvingTurn = false
        moves = 0
        gameStartDate = Date()
        elapsedTime = 0
        hasRecordedCurrentGame = false
    }

    private func gameLayout(in size: CGSize) -> GameLayout {
        let horizontalPadding: CGFloat = 20
        let verticalPadding: CGFloat = 24
        let topAreaHeight: CGFloat = 92
        let buttonHeight: CGFloat = 52
        let sectionSpacing: CGFloat = 14
        let cardSpacing: CGFloat = 5
        let totalCards = cards.count

        let columnsCount = difficulty.columnCount
        let rowsCount = Int(ceil(Double(totalCards) / Double(columnsCount)))
        let availableWidth = size.width - horizontalPadding
        let availableHeight = size.height - verticalPadding - topAreaHeight - buttonHeight - sectionSpacing
        let totalHorizontalSpacing = CGFloat(max(columnsCount - 1, 0)) * cardSpacing
        let totalVerticalSpacing = CGFloat(max(rowsCount - 1, 0)) * cardSpacing
        let cardWidth = max((availableWidth - totalHorizontalSpacing) / CGFloat(columnsCount), 64)
        let cardHeight = max((availableHeight - totalVerticalSpacing) / CGFloat(rowsCount), 98)
        let fittedHeight = min(cardHeight, cardWidth * 1.72)
        let columns = Array(repeating: GridItem(.flexible(), spacing: cardSpacing), count: columnsCount)

        return GameLayout(columns: columns, spacing: cardSpacing, cardHeight: fittedHeight)
    }

    private func recordGameIfNeeded() {
        guard !hasRecordedCurrentGame else { return }

        let result = GameResult(
            playedAt: Date(),
            moves: moves,
            duration: elapsedTime,
            difficulty: difficulty
        )
        let updatedHistory = ([result] + gameHistory).prefix(100)

        guard let data = try? JSONEncoder().encode(Array(updatedHistory)),
              let encoded = String(data: data, encoding: .utf8) else {
            return
        }

        gameHistoryData = encoded
        hasRecordedCurrentGame = true
    }

    private func clearHistory() {
        gameHistoryData = ""
    }

    private func formattedDuration(_ duration: TimeInterval) -> String {
        let totalSeconds = max(Int(duration.rounded()), 0)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

private struct MemoryCardView: View {
    let card: GameCard
    let height: CGFloat
    let isHighlighted: Bool
    let backStyle: CardBackStyle

    var body: some View {
        ZStack {
            if isHighlighted {
                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.yellow.opacity(0.55),
                                Color.yellow.opacity(0.18),
                                .clear
                            ],
                            center: .center,
                            startRadius: 8,
                            endRadius: height * 0.8
                        )
                    )
                    .scaleEffect(1.08)
            }

            CardBackDesignView(style: backStyle)
                .opacity(card.isFaceUp || card.isMatched ? 0 : 1)
                .rotation3DEffect(.degrees(card.isFaceUp || card.isMatched ? 180 : 0), axis: (x: 0, y: 1, z: 0))

            CardArtworkView(name: card.assetName)
                .opacity(card.isFaceUp || card.isMatched ? 1 : 0)
                .rotation3DEffect(.degrees(card.isFaceUp || card.isMatched ? 0 : -180), axis: (x: 0, y: 1, z: 0))
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(isHighlighted ? Color.yellow.opacity(0.95) : .clear, lineWidth: 3)
        }
        .shadow(color: isHighlighted ? Color.yellow.opacity(0.65) : .black.opacity(0.18), radius: isHighlighted ? 18 : 8, y: 4)
        .opacity(card.isMatched ? 0.75 : 1)
        .scaleEffect(isHighlighted ? 1.04 : 1)
        .animation(.easeInOut(duration: 0.25), value: card.isFaceUp)
        .animation(.easeInOut(duration: 0.25), value: card.isMatched)
        .animation(.easeOut(duration: 0.2), value: isHighlighted)
    }
}

private struct CardArtworkView: View {
    let name: String

    var body: some View {
        Group {
            if let image = CardImageLoader.image(named: name) {
                cardImageView(image)
            } else {
                RoundedRectangle(cornerRadius: 10)
                    .fill(.white.opacity(0.12))
                    .overlay {
                        Text(name)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.7))
                            .multilineTextAlignment(.center)
                            .padding(6)
                    }
            }
        }
        .padding(4)
    }

    @ViewBuilder
    private func cardImageView(_ image: PlatformImage) -> some View {
        #if canImport(UIKit)
        Image(uiImage: image)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
        #elseif canImport(AppKit)
        Image(nsImage: image)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
        #endif
    }
}

private enum CardImageLoader {
    static func image(named name: String) -> PlatformImage? {
        #if canImport(UIKit)
        if let image = UIImage(named: name) {
            return image
        }
        #elseif canImport(AppKit)
        if let image = NSImage(named: name) {
            return image
        }
        #endif

        let bundles = Bundle.allBundles + Bundle.allFrameworks

        for bundle in bundles {
            #if canImport(UIKit)
            if let image = UIImage(named: name, in: bundle, compatibleWith: nil) {
                return image
            }
            #elseif canImport(AppKit)
            if let image = bundle.image(forResource: name) {
                return image
            }
            #endif

            if let url = bundle.url(forResource: name, withExtension: "png") {
                #if canImport(UIKit)
                if let image = UIImage(contentsOfFile: url.path) {
                    return image
                }
                #elseif canImport(AppKit)
                if let image = NSImage(contentsOf: url) {
                    return image
                }
                #endif
            }
        }

        return nil
    }
}

private enum CardBackStyle: String, CaseIterable, Identifiable {
    case mondrian
    case flames
    case honeycomb
    case diamonds
    case dots

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mondrian:
            "グリッド"
        case .flames:
            "フレイム"
        case .honeycomb:
            "ハニカム"
        case .diamonds:
            "ダイヤ"
        case .dots:
            "ドット"
        }
    }
}

private struct CardBackPickerOverlay: View {
    let selectedStyle: CardBackStyle
    let onSelect: (CardBackStyle) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 14), count: 2)

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 14) {
                Text("カード裏面を選択")
                    .font(.headline.bold())
                    .foregroundStyle(.white)

                Text("ゲーム開始前に1つ選んでください")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.76))

                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(CardBackStyle.allCases) { style in
                        Button {
                            onSelect(style)
                        } label: {
                            VStack(spacing: 8) {
                                CardBackDesignView(style: style)
                                    .frame(height: 130)
                                    .clipShape(RoundedRectangle(cornerRadius: 16))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 16)
                                            .stroke(selectedStyle == style ? Color.white : .white.opacity(0.22), lineWidth: selectedStyle == style ? 3 : 1)
                                    }

                                Text(style.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.white)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(18)
            .background(Color.black.opacity(0.36))
            .clipShape(RoundedRectangle(cornerRadius: 22))
            .padding(18)
        }
    }
}

private struct CardBackDesignView: View {
    let style: CardBackStyle

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size

            ZStack {
                switch style {
                case .mondrian:
                    MondrianBackView(size: size)
                case .flames:
                    FlameBackView(size: size)
                case .honeycomb:
                    HoneycombBackView(size: size)
                case .diamonds:
                    DiamondBackView(size: size)
                case .dots:
                    DotBackView(size: size)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .padding(4)
    }
}

private struct MondrianBackView: View {
    let size: CGSize

    private let tiles: [MondrianTile] = [
        .init(x: 0.12, y: 0.10, width: 0.10, height: 0.08, color: .cyan),
        .init(x: 0.28, y: 0.21, width: 0.08, height: 0.14, color: .purple.opacity(0.35)),
        .init(x: 0.40, y: 0.30, width: 0.15, height: 0.12, color: .red),
        .init(x: 0.18, y: 0.58, width: 0.08, height: 0.16, color: .black),
        .init(x: 0.72, y: 0.53, width: 0.20, height: 0.14, color: .blue.opacity(0.85)),
        .init(x: 0.86, y: 0.17, width: 0.10, height: 0.10, color: .green),
        .init(x: 0.80, y: 0.78, width: 0.06, height: 0.18, color: .black),
        .init(x: 0.22, y: 0.74, width: 0.14, height: 0.08, color: .blue.opacity(0.85)),
        .init(x: 0.48, y: 0.90, width: 0.10, height: 0.08, color: .green),
        .init(x: 0.62, y: 0.66, width: 0.07, height: 0.14, color: .cyan.opacity(0.45))
    ]

    var body: some View {
        ZStack {
            Color.white

            Path { path in
                let stepX = size.width / 10
                let stepY = size.height / 12

                for index in 0...10 {
                    let x = CGFloat(index) * stepX
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: size.height))
                }

                for index in 0...12 {
                    let y = CGFloat(index) * stepY
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                }
            }
            .stroke(Color.black.opacity(0.18), lineWidth: 1)

            Path { path in
                let thickX: [CGFloat] = [0.18, 0.50, 0.76]
                let thickY: [CGFloat] = [0.20, 0.44, 0.74]

                for ratio in thickX {
                    let x = ratio * size.width
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: size.height))
                }

                for ratio in thickY {
                    let y = ratio * size.height
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                }
            }
            .stroke(.black, lineWidth: 4)

            ForEach(Array(tiles.enumerated()), id: \.offset) { _, tile in
                Rectangle()
                    .fill(tile.color)
                    .frame(width: size.width * tile.width, height: size.height * tile.height)
                    .position(x: size.width * tile.x, y: size.height * tile.y)
            }
        }
    }
}

private struct FlameBackView: View {
    let size: CGSize

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.12, green: 0.34, blue: 0.74), .white, Color(red: 0.12, green: 0.34, blue: 0.74)],
                startPoint: .leading,
                endPoint: .trailing
            )

            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    LinearGradient(colors: [.green, .yellow, .orange], startPoint: .top, endPoint: .bottom),
                    lineWidth: 6
                )

            FlameColumnView(direction: .leading)
            FlameColumnView(direction: .trailing)
        }
    }
}

private struct FlameColumnView: View {
    let direction: HorizontalEdge

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height

            VStack(spacing: height * 0.03) {
                ForEach(0..<5) { index in
                    FlameShape()
                        .fill(
                            LinearGradient(
                                colors: [.purple, .red, .orange, .black],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay {
                            FlameShape()
                                .stroke(.white, lineWidth: 3)
                        }
                        .frame(width: width * 0.30, height: height * 0.17)
                        .rotationEffect(direction == .leading ? .degrees(0) : .degrees(180))
                        .offset(x: direction == .leading ? -width * 0.28 : width * 0.28, y: CGFloat(index.isMultiple(of: 2) ? 0 : 4))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: direction == .leading ? .leading : .trailing)
            .padding(.vertical, height * 0.07)
        }
    }
}

private struct HoneycombBackView: View {
    let size: CGSize

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.56, green: 0.32, blue: 0.02), Color.yellow, Color(red: 0.56, green: 0.32, blue: 0.02)],
                startPoint: .leading,
                endPoint: .trailing
            )

            HexGridPattern(strokeColor: .white, columns: 8, rows: 12)

            Circle()
                .fill(.white)
                .frame(width: size.width * 0.08)
                .position(x: size.width * 0.18, y: size.height * 0.12)

            Circle()
                .fill(.white)
                .frame(width: size.width * 0.08)
                .position(x: size.width * 0.82, y: size.height * 0.88)
        }
    }
}

private struct DiamondBackView: View {
    let size: CGSize

    var body: some View {
        ZStack {
            Color.white
            DiamondPattern()
                .stroke(Color.blue, lineWidth: 8)
        }
    }
}

private struct DotBackView: View {
    let size: CGSize

    private let stripeColors: [Color] = [
        .black, .purple, .cyan, .green, .yellow, .orange, .red, .yellow, .green, .cyan, .blue, .purple, .black
    ]

    var body: some View {
        ZStack {
            Color.white

            ForEach(Array(stripeColors.enumerated()), id: \.offset) { index, color in
                let y = size.height * (CGFloat(index) + 1) / CGFloat(stripeColors.count + 1)

                ForEach(0..<8, id: \.self) { column in
                    let baseX = size.width * (CGFloat(column) + 0.5) / 8
                    let radius = size.width * (0.028 + CGFloat((column + index) % 4) * 0.01)

                    Circle()
                        .fill(color)
                        .frame(width: radius * 2, height: radius * 2)
                        .position(x: baseX + (index.isMultiple(of: 2) ? 0 : size.width * 0.04), y: y)

                    Circle()
                        .fill(color)
                        .frame(width: radius * 0.7, height: radius * 0.7)
                        .position(x: baseX + size.width * 0.055, y: y + size.height * 0.03)
                }
            }
        }
    }
}

private struct MondrianTile {
    let x: CGFloat
    let y: CGFloat
    let width: CGFloat
    let height: CGFloat
    let color: Color
}

private struct FlameShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.12, y: rect.maxY))
        path.addCurve(
            to: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.1),
            control1: CGPoint(x: rect.minX, y: rect.height * 0.68),
            control2: CGPoint(x: rect.width * 0.18, y: rect.minY)
        )
        path.addCurve(
            to: CGPoint(x: rect.maxX - rect.width * 0.08, y: rect.height * 0.54),
            control1: CGPoint(x: rect.width * 0.82, y: rect.height * 0.05),
            control2: CGPoint(x: rect.maxX, y: rect.height * 0.18)
        )
        path.addCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.12, y: rect.maxY),
            control1: CGPoint(x: rect.width * 0.74, y: rect.maxY),
            control2: CGPoint(x: rect.width * 0.24, y: rect.maxY)
        )
        return path
    }
}

private struct HexGridPattern: View {
    let strokeColor: Color
    let columns: Int
    let rows: Int

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width / CGFloat(columns)
            let height = proxy.size.height / CGFloat(rows)

            ForEach(0..<rows, id: \.self) { row in
                ForEach(0..<columns, id: \.self) { column in
                    HexagonShape()
                        .stroke(strokeColor.opacity(0.92), lineWidth: 2)
                        .frame(width: width * 1.08, height: height * 1.08)
                        .position(
                            x: width * (CGFloat(column) + 0.5 + (row.isMultiple(of: 2) ? 0 : 0.5)),
                            y: height * (CGFloat(row) + 0.5)
                        )
                }
            }
        }
    }
}

private struct HexagonShape: Shape {
    func path(in rect: CGRect) -> Path {
        let points = [
            CGPoint(x: rect.midX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.25),
            CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.75),
            CGPoint(x: rect.midX, y: rect.maxY),
            CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.75),
            CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.25)
        ]

        var path = Path()
        path.addLines(points)
        path.closeSubpath()
        return path
    }
}

private struct DiamondPattern: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let spacing = rect.width / 12

        for row in -2...14 {
            for column in -2...12 {
                let centerX = CGFloat(column) * spacing + (row.isMultiple(of: 2) ? 0 : spacing / 2)
                let centerY = CGFloat(row) * spacing
                let diamond = CGRect(x: centerX, y: centerY, width: spacing * 0.8, height: spacing * 0.8)

                path.move(to: CGPoint(x: diamond.midX, y: diamond.minY))
                path.addLine(to: CGPoint(x: diamond.maxX, y: diamond.midY))
                path.addLine(to: CGPoint(x: diamond.midX, y: diamond.maxY))
                path.addLine(to: CGPoint(x: diamond.minX, y: diamond.midY))
                path.closeSubpath()
            }
        }

        return path
    }
}

private struct GameCard: Identifiable {
    let id = UUID()
    let assetName: String
    var isFaceUp = false
    var isMatched = false

    static func makeDeck(pairCount: Int) -> [GameCard] {
        let suits = ["spades", "hearts", "diamonds", "clubs"]
        let ranks = ["A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K"]
        let assetNames = suits.flatMap { suit in
            ranks.map { rank in
                "card-\(suit)-\(rank)"
            }
        }
        let selectedPairs = Array(assetNames.shuffled().prefix(pairCount))

        return (selectedPairs + selectedPairs)
            .shuffled()
            .map { GameCard(assetName: $0) }
    }
}

private enum GameDifficulty: String, CaseIterable, Identifiable, Codable {
    case beginner
    case intermediate
    case advanced

    var id: String { rawValue }

    var title: String {
        switch self {
        case .beginner:
            "初級"
        case .intermediate:
            "中級"
        case .advanced:
            "上級"
        }
    }

    var pairCount: Int {
        switch self {
        case .beginner:
            6
        case .intermediate:
            8
        case .advanced:
            10
        }
    }

    var columnCount: Int {
        switch self {
        case .beginner:
            4
        case .intermediate:
            4
        case .advanced:
            5
        }
    }
}

private struct GameLayout {
    let columns: [GridItem]
    let spacing: CGFloat
    let cardHeight: CGFloat
}

private struct GameResult: Codable, Identifiable {
    let playedAt: Date
    let moves: Int
    let duration: TimeInterval
    let difficulty: GameDifficulty

    var id: TimeInterval { playedAt.timeIntervalSince1970 }
}

private struct GameStatistics {
    let summaries: [DifficultySummary]

    init(history: [GameResult]) {
        summaries = GameDifficulty.allCases.map { difficulty in
            DifficultySummary(difficulty: difficulty, history: history.filter { $0.difficulty == difficulty })
        }
    }
}

private struct StatusSummaryView: View {
    let movesText: String
    let timeText: String
    let progressText: String
    let isCompleted: Bool

    var body: some View {
        HStack(spacing: 8) {
            StatusChipView(title: "手数", value: movesText)
            StatusChipView(title: "時間", value: timeText)
            StatusChipView(title: "ペア", value: progressText)
        }
        .padding(.top, 2)
    }
}

private struct StatusChipView: View {
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.72))

            Text(value)
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(.white.opacity(0.94))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color.white.opacity(0.1))
        .clipShape(Capsule())
    }
}

private struct ScoreSummaryView: View {
    let stats: GameStatistics

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("スコア")
                .font(.subheadline.bold())
                .foregroundStyle(.white)

            ScrollView(.horizontal, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 6) {
                    DifficultyScoreHeaderRow()

                    ForEach(stats.summaries) { summary in
                        DifficultyScoreRow(summary: summary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct DifficultyScoreHeaderRow: View {
    var body: some View {
        HStack(spacing: 10) {
            header("レベル", width: 38)
            header("回数", width: 44)
            header("最短手数", width: 76)
            header("最短時間", width: 86)
            header("平均手数", width: 76)
            header("平均時間", width: 86)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
    }

    private func header(_ title: String, width: CGFloat) -> some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.white.opacity(0.72))
            .frame(width: width, alignment: .leading)
    }
}

private struct DifficultySummary: Identifiable {
    let difficulty: GameDifficulty
    let gameCount: Int
    let averageMoves: Double
    let averageDuration: TimeInterval
    let bestMoves: Int?
    let bestDuration: TimeInterval?

    var id: GameDifficulty { difficulty }

    init(difficulty: GameDifficulty, history: [GameResult]) {
        self.difficulty = difficulty
        gameCount = history.count
        averageMoves = history.isEmpty ? 0 : Double(history.map(\.moves).reduce(0, +)) / Double(history.count)
        averageDuration = history.isEmpty ? 0 : history.map(\.duration).reduce(0, +) / Double(history.count)
        bestMoves = history.map(\.moves).min()
        bestDuration = history.map(\.duration).min()
    }
}

private struct DifficultyScoreRow: View {
    let summary: DifficultySummary

    var body: some View {
        HStack(spacing: 10) {
            Text(summary.difficulty.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 38, alignment: .leading)

            Text("回数 \(summary.gameCount)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.white.opacity(0.82))
                .frame(width: 44, alignment: .leading)

            Text("最短手数 \(summary.bestMoves.map(String.init) ?? "-")")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.white.opacity(0.82))
                .frame(width: 76, alignment: .leading)

            Text("最短時間 \(summary.bestDuration?.clockString ?? "-")")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.white.opacity(0.82))
                .frame(width: 86, alignment: .leading)

            Text("平均手数 \(summary.gameCount == 0 ? "-" : String(format: "%.1f", summary.averageMoves))")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.white.opacity(0.82))
                .frame(width: 76, alignment: .leading)

            Text("平均時間 \(summary.gameCount == 0 ? "-" : summary.averageDuration.clockString)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.white.opacity(0.82))
                .frame(width: 86, alignment: .leading)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

private struct ScoreHistoryView: View {
    let history: [GameResult]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("直近10回")
                .font(.subheadline.bold())
                .foregroundStyle(.white)

            if history.isEmpty {
                Text("まだ履歴がありません")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.75))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                VStack(spacing: 4) {
                    ForEach(Array(history.enumerated()), id: \.element.id) { offset, result in
                        HStack {
                            Text("\(offset + 1).")
                                .frame(width: 22, alignment: .leading)

                            Text(result.difficulty.title)
                                .frame(width: 30, alignment: .leading)

                            Text("\(result.moves)手")
                                .frame(width: 52, alignment: .leading)

                            Text(result.duration.clockString)
                                .frame(width: 54, alignment: .leading)

                            Text(result.playedAt.formatted(date: .numeric, time: .shortened))
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.88))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private extension TimeInterval {
    var clockString: String {
        let totalSeconds = max(Int(rounded()), 0)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
