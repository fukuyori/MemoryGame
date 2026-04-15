//
//  ContentView.swift
//  SimpleMemoryGame
//
//  Created by 福寄典明 on 2026/04/14.
//

import SwiftUI
import Combine
import WebKit

struct ContentView: View {
    @AppStorage("gameHistoryV2") private var gameHistoryData = ""
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
    @State private var cardBackStyle: CardBackStyle
    @State private var completionMessage: String?
    @State private var completionMessageTone: CompletionMessageTone = .neutral
    @State private var showsConfetti = false

    init() {
        let savedDifficulty = GameDifficulty(rawValue: UserDefaults.standard.string(forKey: "selectedDifficulty") ?? "") ?? .intermediate
        _difficulty = State(initialValue: savedDifficulty)
        _cards = State(initialValue: GameCard.makeDeck(pairCount: savedDifficulty.pairCount))
        _cardBackStyle = State(initialValue: CardBackStyle.randomStyle())
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
                                        width: layout.cardWidth,
                                        height: layout.cardHeight,
                                        isHighlighted: recentlyMatchedIndices.contains(index),
                                        backStyle: cardBackStyle
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

            if showsConfetti {
                ConfettiOverlay()
                    .allowsHitTesting(false)
            }

            if let completionMessage {
                CompletionMessageBanner(
                    message: completionMessage,
                    tone: completionMessageTone
                )
                .padding(.top, 24)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: completionMessage != nil)
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
        cardBackStyle = CardBackStyle.randomStyle()
        selectedIndices.removeAll()
        recentlyMatchedIndices.removeAll()
        isResolvingTurn = false
        moves = 0
        gameStartDate = Date()
        elapsedTime = 0
        hasRecordedCurrentGame = false
        completionMessage = nil
        showsConfetti = false
    }

    private func gameLayout(in size: CGSize) -> GameLayout {
        let isLandscape = size.width > size.height
        let horizontalPadding: CGFloat = 20
        let verticalPadding: CGFloat = 24
        let topAreaHeight: CGFloat = 78
        let buttonHeight: CGFloat = 48
        let sectionSpacing: CGFloat = 12
        let cardSpacing: CGFloat = size.height < 760 ? 4 : 5
        let totalCards = cards.count

        let columnsCount = difficulty.columnCount(isLandscape: isLandscape)
        let rowsCount = Int(ceil(Double(totalCards) / Double(columnsCount)))
        let availableWidth = max(size.width - horizontalPadding, 0)
        let availableHeight = max(size.height - verticalPadding - topAreaHeight - buttonHeight - sectionSpacing, 0)
        let totalHorizontalSpacing = CGFloat(max(columnsCount - 1, 0)) * cardSpacing
        let totalVerticalSpacing = CGFloat(max(rowsCount - 1, 0)) * cardSpacing
        let widthDrivenCardWidth = (availableWidth - totalHorizontalSpacing) / CGFloat(columnsCount)
        let heightDrivenCardHeight = (availableHeight - totalVerticalSpacing) / CGFloat(rowsCount)
        let aspectRatio: CGFloat = 1.72
        let fittedHeight = min(heightDrivenCardHeight, widthDrivenCardWidth * aspectRatio)
        let fittedWidth = min(widthDrivenCardWidth, fittedHeight / aspectRatio)
        let safeCardWidth = max(fittedWidth, 40)
        let safeCardHeight = max(fittedHeight, 68)
        let columns = Array(repeating: GridItem(.fixed(safeCardWidth), spacing: cardSpacing), count: columnsCount)

        return GameLayout(columns: columns, spacing: cardSpacing, cardWidth: safeCardWidth, cardHeight: safeCardHeight)
    }

    private func recordGameIfNeeded() {
        guard !hasRecordedCurrentGame else { return }

        let previousHistory = gameHistory.filter { $0.difficulty == difficulty }

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
        showCompletionFeedback(for: result, previousHistory: previousHistory)
    }

    private func clearHistory() {
        gameHistoryData = ""
    }

    private func showCompletionFeedback(for result: GameResult, previousHistory: [GameResult]) {
        let feedback = completionFeedback(for: result, previousHistory: previousHistory)
        completionMessage = feedback?.message
        completionMessageTone = feedback?.tone ?? .neutral
        showsConfetti = feedback?.tone == .celebration

        guard feedback != nil else { return }

        Task {
            try? await Task.sleep(for: .seconds(3))
            completionMessage = nil
            showsConfetti = false
        }
    }

    private func completionFeedback(for result: GameResult, previousHistory: [GameResult]) -> CompletionFeedback? {
        if previousHistory.count >= 1 {
            if let previousBestMoves = previousHistory.map(\.moves).min(),
               result.moves < previousBestMoves {
                return CompletionFeedback(message: "おめでとう！　最小手数が更新されました！", tone: .celebration)
            }

            if let previousBestDuration = previousHistory.map(\.duration).min(),
               result.duration < previousBestDuration {
                return CompletionFeedback(message: "おめでとう！　最短時間が更新されました！", tone: .celebration)
            }

            if let previousWorstMoves = previousHistory.map(\.moves).max(),
               result.moves > previousWorstMoves {
                return CompletionFeedback(message: "最大手数が更新されました。", tone: .warning)
            }

            if let previousWorstDuration = previousHistory.map(\.duration).max(),
               result.duration > previousWorstDuration {
                return CompletionFeedback(message: "最大時間が更新されました。", tone: .warning)
            }
        }

        if previousHistory.count >= 2 {
            let averageMoves = Double(previousHistory.map(\.moves).reduce(0, +)) / Double(previousHistory.count)
            let averageDuration = previousHistory.map(\.duration).reduce(0, +) / Double(previousHistory.count)

            if Double(result.moves) < averageMoves, result.duration < averageDuration {
                return CompletionFeedback(message: "いい調子です！", tone: .positive)
            }

            if Double(result.moves) > averageMoves, result.duration > averageDuration {
                return CompletionFeedback(message: "がんばって！", tone: .warning)
            }
        }

        return nil
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
    let width: CGFloat
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
        .frame(width: width)
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
        if let resource = SVGCardResource(name: name) {
            SVGCardView(resource: resource)
                .padding(2)
        } else if let cardFace = StandardCardFace(name: name) {
            StandardCardFaceView(face: cardFace)
                .padding(4)
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
                .padding(4)
        }
    }
}

private struct SVGCardResource: Equatable {
    let fileName: String

    init?(name: String) {
        let parts = name.split(separator: "-")
        guard parts.count == 3 else {
            return nil
        }

        let suitCode: String
        switch parts[1] {
        case "spades":
            suitCode = "S"
        case "hearts":
            suitCode = "H"
        case "diamonds":
            suitCode = "D"
        case "clubs":
            suitCode = "C"
        default:
            return nil
        }

        let rankCode: String
        switch parts[2] {
        case "10":
            rankCode = "T"
        default:
            rankCode = String(parts[2])
        }

        let candidate = "\(rankCode)\(suitCode)"
        guard Bundle.main.url(forResource: candidate, withExtension: "svg") != nil else {
            return nil
        }

        fileName = candidate
    }

    var fileURL: URL? {
        Bundle.main.url(forResource: fileName, withExtension: "svg")
    }
}

private struct SVGCardView: UIViewRepresentable {
    let resource: SVGCardResource

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.isUserInteractionEnabled = false
        webView.contentMode = .scaleAspectFit
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.loadedFileName != resource.fileName,
              let fileURL = resource.fileURL else {
            return
        }

        context.coordinator.loadedFileName = resource.fileName

        let html = """
        <!doctype html>
        <html>
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
        <style>
        html, body {
          margin: 0;
          padding: 0;
          width: 100%;
          height: 100%;
          background: transparent;
          overflow: hidden;
        }
        body {
          display: flex;
          align-items: center;
          justify-content: center;
        }
        img {
          width: 100%;
          height: 100%;
          object-fit: contain;
          display: block;
        }
        </style>
        </head>
        <body>
          <img src="\(resource.fileName).svg" />
        </body>
        </html>
        """

        webView.loadHTMLString(html, baseURL: fileURL.deletingLastPathComponent())
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        var loadedFileName: String?
    }
}

private struct StandardCardFace {
    let rank: String
    let suit: CardSuit

    init?(name: String) {
        let parts = name.split(separator: "-")
        guard parts.count == 3,
              let suit = CardSuit(rawValue: String(parts[1])) else {
            return nil
        }

        self.rank = String(parts[2])
        self.suit = suit
    }

    var isFaceCard: Bool {
        ["J", "Q", "K"].contains(rank)
    }

    var displayRank: String {
        rank
    }

    var courtTitle: String {
        switch rank {
        case "J": "JACK"
        case "Q": "QUEEN"
        case "K": "KING"
        default: rank
        }
    }

    var courtSymbol: String {
        switch rank {
        case "J": "⚔"
        case "Q": "❦"
        case "K": "♛"
        default: suit.symbol
        }
    }

    var pipLayout: [CardPip] {
        switch rank {
        case "2":
            return [.init(x: 0, y: 0.18), .init(x: 0, y: 0.82, isInverted: true)]
        case "3":
            return [.init(x: 0, y: 0.18), .init(x: 0, y: 0.50), .init(x: 0, y: 0.82, isInverted: true)]
        case "4":
            return pairedRows([0.22, 0.78])
        case "5":
            return pairedRows([0.22, 0.78]) + [.init(x: 0, y: 0.50)]
        case "6":
            return pairedRows([0.18, 0.50, 0.82])
        case "7":
            return [.init(x: 0, y: 0.12)] + pairedRows([0.28, 0.56, 0.82])
        case "8":
            return pairedRows([0.14, 0.36, 0.64, 0.86])
        case "9":
            return pairedRows([0.14, 0.34, 0.66, 0.86]) + [.init(x: 0, y: 0.50)]
        case "10":
            return [.init(x: 0, y: 0.12), .init(x: 0, y: 0.88, isInverted: true)] + pairedRows([0.26, 0.50, 0.74])
        default:
            return []
        }
    }

    private func pairedRows(_ rows: [CGFloat]) -> [CardPip] {
        rows.flatMap { y in
            [
                CardPip(x: -0.26, y: y, isInverted: y > 0.5),
                CardPip(x: 0.26, y: y, isInverted: y > 0.5)
            ]
        }
    }
}

private struct CardPip: Identifiable {
    let id = UUID()
    let x: CGFloat
    let y: CGFloat
    let isInverted: Bool

    init(x: CGFloat, y: CGFloat, isInverted: Bool = false) {
        self.x = x
        self.y = y
        self.isInverted = isInverted
    }
}

private enum CardSuit: String {
    case spades
    case hearts
    case diamonds
    case clubs

    var symbol: String {
        switch self {
        case .spades: "♠"
        case .hearts: "♥"
        case .diamonds: "♦"
        case .clubs: "♣"
        }
    }

    var color: Color {
        switch self {
        case .hearts, .diamonds:
            Color(red: 0.73, green: 0.09, blue: 0.13)
        case .spades, .clubs:
            Color(red: 0.1, green: 0.1, blue: 0.13)
        }
    }
}

private struct StandardCardFaceView: View {
    let face: StandardCardFace

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let cornerRankSize = max(size.width * 0.22, 12)
            let cornerSuitSize = max(size.width * 0.16, 10)

            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.white)
                    .overlay {
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.black.opacity(0.18), lineWidth: 1)
                    }

                VStack {
                    HStack(alignment: .top) {
                        cornerMark(rankSize: cornerRankSize, suitSize: cornerSuitSize)
                        Spacer(minLength: 0)
                    }
                    .padding(.top, size.height * 0.08)
                    .padding(.leading, size.width * 0.1)

                    Spacer(minLength: 0)

                    centerArtwork(in: size)

                    Spacer(minLength: 0)

                    HStack(alignment: .bottom) {
                        Spacer(minLength: 0)
                        cornerMark(rankSize: cornerRankSize, suitSize: cornerSuitSize)
                            .rotationEffect(.degrees(180))
                    }
                    .padding(.bottom, size.height * 0.08)
                    .padding(.trailing, size.width * 0.1)
                }
            }
        }
    }

    @ViewBuilder
    private func centerArtwork(in size: CGSize) -> some View {
        if face.rank == "A" {
            Text(face.suit.symbol)
                .font(.system(size: min(size.width * 0.42, size.height * 0.34), weight: .regular, design: .serif))
                .foregroundStyle(face.suit.color)
        } else if face.isFaceCard {
            faceCardArtwork(in: size)
        } else {
            numberCardArtwork(in: size)
        }
    }

    private func numberCardArtwork(in size: CGSize) -> some View {
        ZStack {
            ForEach(face.pipLayout) { pip in
                Text(face.suit.symbol)
                    .font(.system(size: min(size.width * 0.17, size.height * 0.105), weight: .regular, design: .serif))
                    .foregroundStyle(face.suit.color)
                    .rotationEffect(pip.isInverted ? .degrees(180) : .zero)
                    .position(
                        x: size.width * (0.50 + pip.x),
                        y: size.height * (0.16 + pip.y * 0.68)
                    )
            }
        }
    }

    private func faceCardArtwork(in size: CGSize) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(face.suit.color.opacity(0.06))
                .frame(width: size.width * 0.60, height: size.height * 0.64)

            RoundedRectangle(cornerRadius: 12)
                .stroke(face.suit.color.opacity(0.22), lineWidth: 1)
                .frame(width: size.width * 0.60, height: size.height * 0.64)

            VStack(spacing: 0) {
                courtHalf(in: size)
                    .frame(height: size.height * 0.24)

                ZStack {
                    Capsule()
                        .fill(face.suit.color.opacity(0.10))
                        .frame(width: size.width * 0.34, height: size.height * 0.09)

                    Text(face.suit.symbol)
                        .font(.system(size: min(size.width * 0.16, size.height * 0.10), weight: .regular, design: .serif))
                        .foregroundStyle(face.suit.color)
                }
                .padding(.vertical, size.height * 0.02)

                courtHalf(in: size)
                    .rotationEffect(.degrees(180))
                    .frame(height: size.height * 0.24)
            }
        }
    }

    private func courtHalf(in size: CGSize) -> some View {
        HStack(spacing: size.width * 0.04) {
            VStack(spacing: size.height * 0.008) {
                Text(face.rank)
                    .font(.system(size: min(size.width * 0.17, size.height * 0.10), weight: .bold, design: .serif))
                    .foregroundStyle(face.suit.color)

                Text(face.suit.symbol)
                    .font(.system(size: min(size.width * 0.11, size.height * 0.07), weight: .regular, design: .serif))
                    .foregroundStyle(face.suit.color)
            }
            .frame(width: size.width * 0.11)

            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white)
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(face.suit.color.opacity(0.18), lineWidth: 1)
                    }

                VStack(spacing: size.height * 0.004) {
                    Text(face.courtTitle)
                        .font(.system(size: min(size.width * 0.07, size.height * 0.042), weight: .bold, design: .serif))
                        .tracking(0.6)
                        .foregroundStyle(face.suit.color.opacity(0.82))

                    Text(face.courtSymbol)
                        .font(.system(size: min(size.width * 0.13, size.height * 0.08), weight: .regular, design: .serif))
                        .foregroundStyle(face.suit.color)

                    Text(face.suit.symbol)
                        .font(.system(size: min(size.width * 0.14, size.height * 0.09), weight: .regular, design: .serif))
                        .foregroundStyle(face.suit.color)
                }
                .padding(.vertical, size.height * 0.01)
            }
            .frame(width: size.width * 0.34, height: size.height * 0.18)
        }
    }

    private func cornerMark(rankSize: CGFloat, suitSize: CGFloat) -> some View {
        VStack(spacing: -2) {
            Text(face.rank)
                .font(.system(size: rankSize, weight: .bold, design: .serif))
                .foregroundStyle(face.suit.color)
                .minimumScaleFactor(0.65)
            Text(face.suit.symbol)
                .font(.system(size: suitSize, weight: .regular, design: .serif))
                .foregroundStyle(face.suit.color)
        }
        .lineLimit(1)
    }
}

private enum CardBackStyle: String, CaseIterable, Identifiable {
    case classicBlue
    case classicRed
    case blueCrosshatch
    case redCrosshatch

    var id: String { rawValue }

    var title: String {
        switch self {
        case .classicBlue:
            "青ダイヤ"
        case .classicRed:
            "赤ダイヤ"
        case .blueCrosshatch:
            "青格子"
        case .redCrosshatch:
            "赤格子"
        }
    }

    static func randomStyle() -> CardBackStyle {
        allCases.randomElement() ?? .classicBlue
    }
}

private struct CardBackDesignView: View {
    let style: CardBackStyle

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size

            ZStack {
                switch style {
                case .classicBlue:
                    ClassicBlueBackView(size: size)
                case .classicRed:
                    ClassicRedBackView(size: size)
                case .blueCrosshatch:
                    BlueCrosshatchBackView(size: size)
                case .redCrosshatch:
                    RedCrosshatchBackView(size: size)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .padding(4)
    }
}

private struct ClassicBlueBackView: View {
    let size: CGSize

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.08, green: 0.23, blue: 0.58),
                    Color(red: 0.12, green: 0.31, blue: 0.69)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RoundedRectangle(cornerRadius: 12)
                .inset(by: size.width * 0.05)
                .stroke(Color.white.opacity(0.95), lineWidth: max(size.width * 0.018, 2))

            RoundedRectangle(cornerRadius: 10)
                .inset(by: size.width * 0.11)
                .stroke(Color.white.opacity(0.65), lineWidth: max(size.width * 0.01, 1))

            ClassicDiamondLattice()
                .stroke(Color.white.opacity(0.35), lineWidth: max(size.width * 0.008, 0.8))
                .padding(size.width * 0.12)

            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.14))
                    .frame(width: size.width * 0.30)

                Circle()
                    .stroke(Color.white.opacity(0.85), lineWidth: max(size.width * 0.012, 1.5))
                    .frame(width: size.width * 0.24)

                Text("◆")
                    .font(.system(size: size.width * 0.13, weight: .bold, design: .serif))
                    .foregroundStyle(Color.white.opacity(0.92))
            }
        }
    }
}

private struct ClassicRedBackView: View {
    let size: CGSize

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.60, green: 0.10, blue: 0.12),
                    Color(red: 0.74, green: 0.16, blue: 0.18)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RoundedRectangle(cornerRadius: 12)
                .inset(by: size.width * 0.05)
                .stroke(Color.white.opacity(0.95), lineWidth: max(size.width * 0.018, 2))

            RoundedRectangle(cornerRadius: 10)
                .inset(by: size.width * 0.11)
                .stroke(Color.white.opacity(0.65), lineWidth: max(size.width * 0.01, 1))

            ClassicDiamondLattice()
                .stroke(Color.white.opacity(0.35), lineWidth: max(size.width * 0.008, 0.8))
                .padding(size.width * 0.12)
        }
    }
}

private struct BlueCrosshatchBackView: View {
    let size: CGSize

    var body: some View {
        ZStack {
            Color(red: 0.10, green: 0.28, blue: 0.66)

            RoundedRectangle(cornerRadius: 12)
                .inset(by: size.width * 0.05)
                .stroke(Color.white.opacity(0.95), lineWidth: max(size.width * 0.018, 2))

            CrosshatchPattern()
                .stroke(Color.white.opacity(0.28), lineWidth: max(size.width * 0.008, 0.8))
                .padding(size.width * 0.13)

            RoundedRectangle(cornerRadius: 9)
                .inset(by: size.width * 0.18)
                .stroke(Color.white.opacity(0.65), lineWidth: max(size.width * 0.01, 1))
        }
    }
}

private struct RedCrosshatchBackView: View {
    let size: CGSize

    var body: some View {
        ZStack {
            Color(red: 0.66, green: 0.14, blue: 0.16)

            RoundedRectangle(cornerRadius: 12)
                .inset(by: size.width * 0.05)
                .stroke(Color.white.opacity(0.95), lineWidth: max(size.width * 0.018, 2))

            CrosshatchPattern()
                .stroke(Color.white.opacity(0.28), lineWidth: max(size.width * 0.008, 0.8))
                .padding(size.width * 0.13)

            RoundedRectangle(cornerRadius: 9)
                .inset(by: size.width * 0.18)
                .stroke(Color.white.opacity(0.65), lineWidth: max(size.width * 0.01, 1))
        }
    }
}

private struct ClassicDiamondLattice: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let columns = 7
        let rows = 10
        let cellWidth = rect.width / CGFloat(columns)
        let cellHeight = rect.height / CGFloat(rows)
        let diamondWidth = cellWidth * 0.58
        let diamondHeight = cellHeight * 0.58

        for row in 0..<rows {
            for column in 0..<columns {
                let center = CGPoint(
                    x: cellWidth * (CGFloat(column) + 0.5),
                    y: cellHeight * (CGFloat(row) + 0.5)
                )

                path.move(to: CGPoint(x: center.x, y: center.y - diamondHeight / 2))
                path.addLine(to: CGPoint(x: center.x + diamondWidth / 2, y: center.y))
                path.addLine(to: CGPoint(x: center.x, y: center.y + diamondHeight / 2))
                path.addLine(to: CGPoint(x: center.x - diamondWidth / 2, y: center.y))
                path.closeSubpath()
            }
        }

        return path
    }
}

private struct CrosshatchPattern: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let spacing = max(rect.width / 12, 8)
        var x = -rect.height

        while x < rect.width + rect.height {
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x + rect.height, y: rect.height))
            x += spacing
        }

        x = 0
        while x < rect.width + rect.height {
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x - rect.height, y: rect.height))
            x += spacing
        }

        return path
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

    func columnCount(isLandscape: Bool) -> Int {
        switch self {
        case .beginner:
            isLandscape ? 6 : 4
        case .intermediate:
            isLandscape ? 8 : 4
        case .advanced:
            isLandscape ? 10 : 5
        }
    }
}

private struct GameLayout {
    let columns: [GridItem]
    let spacing: CGFloat
    let cardWidth: CGFloat
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

private struct CompletionFeedback {
    let message: String
    let tone: CompletionMessageTone
}

private enum CompletionMessageTone {
    case celebration
    case positive
    case warning
    case neutral

    var backgroundColor: Color {
        switch self {
        case .celebration:
            Color.yellow.opacity(0.22)
        case .positive:
            Color.green.opacity(0.22)
        case .warning:
            Color.orange.opacity(0.24)
        case .neutral:
            Color.white.opacity(0.14)
        }
    }

    var borderColor: Color {
        switch self {
        case .celebration:
            Color.yellow.opacity(0.9)
        case .positive:
            Color.green.opacity(0.9)
        case .warning:
            Color.orange.opacity(0.9)
        case .neutral:
            Color.white.opacity(0.5)
        }
    }
}

private struct CompletionMessageBanner: View {
    let message: String
    let tone: CompletionMessageTone

    var body: some View {
        Text(message)
            .font(.headline.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(tone.backgroundColor)
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(tone.borderColor, lineWidth: 2)
            }
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(color: .black.opacity(0.25), radius: 12, y: 6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, 18)
    }
}

private struct ConfettiOverlay: View {
    private let colors: [Color] = [.yellow, .pink, .cyan, .green, .orange, .white]
    @State private var animate = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ForEach(0..<32, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(colors[index % colors.count])
                        .frame(width: index.isMultiple(of: 3) ? 8 : 6, height: 14)
                        .rotationEffect(.degrees(animate ? Double(index * 37) : Double(index * 12)))
                        .position(
                            x: geometry.size.width * xPosition(for: index),
                            y: animate ? geometry.size.height + 40 : -20
                        )
                        .animation(
                            .easeIn(duration: 1.8)
                                .delay(Double(index) * 0.03),
                            value: animate
                        )
                }
            }
            .onAppear {
                animate = false
                animate = true
            }
        }
    }

    private func xPosition(for index: Int) -> CGFloat {
        let values: [CGFloat] = [0.06, 0.12, 0.18, 0.24, 0.31, 0.37, 0.43, 0.49, 0.55, 0.61, 0.68, 0.74, 0.80, 0.86, 0.92]
        return values[index % values.count]
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
