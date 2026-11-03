//
//  JournalRiskClassifier.swift
//  JournalFoundation
//
//  Conservative lexical screen that maps journal text or a question to a
//  `JournalSafetyLevel`. Every AI surface runs it before analyzing, quoting,
//  or asking about content, and `SensitiveDomainPolicy` turns the level into
//  a response mode.
//
//  It errs toward support: a false positive costs one supportive reply, a
//  miss costs much more. It never diagnoses; it only decides whether a
//  surface may analyze the text.
//
//  Sentence-embedding similarity was tried for indirect wording and rejected:
//  with NLEmbedding, "I can't wait for this project to be over" sat closer to
//  the crisis seeds than most real indirect cues, so no threshold separated
//  them. Indirect wording is listed explicitly instead.
//
//  English and Spanish lists both run on every text, so a journal that mixes
//  languages is still screened. Matching ignores case and accents, so "dano"
//  matches "daño". Spanish figures of speech ("me muero de risa", "me mata el
//  tráfico") stay unflagged because no list holds a bare "muero" or "mata".
//

import Foundation

public enum JournalRiskClassifier {

    /// Safety level for one piece of text.
    public static func level(for text: String) -> JournalSafetyLevel {
        let normalized = normalize(text)
        guard !normalized.isEmpty else { return .none }
        if matches(highRiskPatterns, in: normalized) { return .highRiskExcluded }
        if matches(moderateConcernPatterns, in: normalized) { return .moderateConcern }
        if matches(mildDistressPatterns, in: normalized) { return .mildDistress }
        return .none
    }

    /// The highest safety level across several texts.
    public static func level<Texts: Sequence>(forAll texts: Texts) -> JournalSafetyLevel where Texts.Element == String {
        texts.reduce(JournalSafetyLevel.none) { Swift.max($0, level(for: $1)) }
    }

    /// How a surface should respond to the text under `policy`.
    public static func responseMode(
        for text: String,
        policy: SensitiveDomainPolicy = .standard
    ) -> SensitiveResponseMode {
        policy.responseMode(for: level(for: text))
    }

    // MARK: - Phrases

    /// Direct and indirect references to suicide or self-harm.
    static let highRiskPhrases: [String] = [
        "kill myself", "killing myself", "kill my self",
        "suicide", "suicidal",
        "end my life", "ending my life", "end it all",
        "take my own life", "taking my own life",
        "self harm", "self-harm", "selfharm", "harm myself", "hurt myself", "hurting myself",
        "cut myself", "cutting myself",
        "want to die", "wanna die", "wish i was dead", "wish i were dead", "better off dead",
        "better off without me", "everyone would be better off",
        "if i wasn't here", "if i weren't here", "if i was gone", "if i were gone",
        "no reason to live", "nothing to live for", "not worth living",
        "don't want to live", "do not want to live", "don't want to be alive", "do not want to be alive",
        "don't want to wake up", "never wake up again", "can't go on living",
        "disappear forever",
    ]

    /// Hopelessness and indirect wording that is often, but not always, about risk.
    static let moderateConcernPhrases: [String] = [
        "hopeless", "worthless",
        "can't cope", "cannot cope", "can't take it anymore", "can't do this anymore",
        "no way out", "ending things", "give up on everything",
        "nobody would notice", "nobody would care", "no one would notice", "no one would care",
        "what's the point of anything", "no point in anything", "empty inside",
    ]

    /// Ordinary distress: the surface softens and skips probing questions.
    static let mildDistressPhrases: [String] = [
        "overwhelmed", "exhausted", "panic", "panicked", "panicking", "burned out", "burnt out", "breaking down",
    ]

    // MARK: - Spanish phrases

    // Written with accents for readability; matching folds them. Spanish
    // inflects for gender and person, so each form is listed. Bare "morir",
    // "muero", "mata", "muerta" and "desaparecer" are left out on purpose:
    // they carry most everyday figures of speech.

    /// Direct and indirect references to suicide or self-harm, in Spanish.
    static let spanishHighRiskPhrases: [String] = [
        // Suicide
        "suicidio", "suicida", "suicidas", "suicidarme", "suicidarse",
        "me voy a suicidar", "me quiero suicidar",
        // Killing or ending one's life
        "matarme", "me voy a matar", "me quiero matar",
        "quitarme la vida", "me quito la vida",
        "acabar con mi vida", "terminar con mi vida", "poner fin a mi vida",
        "acabar con todo", "terminar con todo",
        // Self-harm
        "hacerme daño", "lastimarme",
        "autolesión", "autolesiones", "autolesionarme", "autolesionarse",
        "me autolesiono", "me autolesioné", "autolesionándome",
        "cortarme las venas", "cortarme los brazos", "me corto los brazos", "volví a cortarme",
        // Wanting to die or not to live
        "quiero morir", "quiero morirme", "me quiero morir",
        "quisiera morir", "quisiera morirme", "deseo morir", "deseo morirme",
        "ojalá me muriera", "ojalá estuviera muerto", "ojalá estuviera muerta",
        "quiero estar muerto", "quiero estar muerta",
        "estaría mejor muerto", "estaría mejor muerta",
        "no quiero vivir", "no quiero seguir viviendo", "no quiero estar vivo", "no quiero estar viva",
        "no puedo seguir viviendo",
        "no quiero despertar nunca", "no quiero volver a despertar", "ojalá no despertara",
        "no hay razón para vivir", "no tengo razones para vivir", "no tengo razón para vivir",
        "no tengo por qué vivir", "nada por lo que vivir", "no vale la pena vivir", "la vida no vale la pena",
        // Indirect wording
        "estarían mejor sin mí", "estarías mejor sin mí", "estaríais mejor sin mí", "estaría mejor sin mí",
        "todo sería mejor sin mí", "sería mejor sin mí",
        "si yo no estuviera", "si yo ya no estuviera", "si ya no estuviera aquí", "si yo no existiera",
        "desaparecer para siempre", "quiero dejar de existir", "quisiera dejar de existir",
    ]

    /// Hopelessness and indirect wording, in Spanish.
    static let spanishModerateConcernPhrases: [String] = [
        "sin esperanza", "desesperanza", "desesperanzado", "desesperanzada",
        "no puedo más", "ya no puedo más", "no aguanto más", "ya no aguanto",
        "no lo soporto más", "no soporto más", "no puedo seguir así",
        "no hay salida", "no veo salida", "no le veo salida",
        "nada tiene sentido", "para qué seguir",
        "no valgo nada", "no sirvo para nada",
        "a nadie le importaría", "nadie lo notaría", "nadie se daría cuenta",
        "nadie me echaría de menos", "nadie me extrañaría",
        "vacío por dentro", "vacía por dentro",
    ]

    /// Ordinary distress, in Spanish.
    static let spanishMildDistressPhrases: [String] = [
        "agotado", "agotada", "agotados", "agotadas",
        "abrumado", "abrumada", "abrumados", "abrumadas",
        "desbordado", "desbordada",
        "pánico", "ataque de ansiedad", "crisis de ansiedad",
        "estresado", "estresada",
        "estoy quemado", "estoy quemada", "burnout",
        "muerto de cansancio", "muerta de cansancio",
        "me derrumbé", "derrumbarme",
    ]

    /// Words that, right after a Spanish phrase, make it ordinary speech:
    /// "acabar con todo el trabajo" is a to-do list, "acabar con todo" alone
    /// is not.
    static let spanishFigurativeContinuations: [String: Set<String>] = [
        "acabar con todo": ["el", "la", "los", "las", "lo", "mi", "mis", "tu", "tus", "su", "sus", "ese", "esa", "aquello"],
        "terminar con todo": ["el", "la", "los", "las", "lo", "mi", "mis", "tu", "tus", "su", "sus", "ese", "esa", "aquello"],
    ]

    /// Folding accents makes "sin mí" (without me) and "sin mi" (without my)
    /// the same text. After "sin mí" only these words follow; any other word
    /// means "mi" is a possessive ("estarían mejor sin mi jefe").
    static let spanishWordsAfterSinMi: Set<String> = [
        "y", "e", "o", "ni", "que", "de", "en", "para", "porque", "pues", "ya", "asi",
        "aqui", "alli", "nunca", "jamas", "tambien", "todos", "todas", "todo", "mismo", "misma",
    ]

    // Normalized once, in the same form as the text they're matched against.
    private static let highRiskPatterns = patterns(highRiskPhrases + spanishHighRiskPhrases)
    private static let moderateConcernPatterns = patterns(moderateConcernPhrases + spanishModerateConcernPhrases)
    private static let mildDistressPatterns = patterns(mildDistressPhrases + spanishMildDistressPhrases)
    private static let figurativeContinuations: [String: Set<String>] = Dictionary(
        uniqueKeysWithValues: spanishFigurativeContinuations.map { (normalize($0.key), Set($0.value.map(normalize))) }
    )

    private static func patterns(_ phrases: [String]) -> [String] {
        var seen = Set<String>()
        return phrases.map(normalize).filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    // MARK: - Matching

    static func normalize(_ text: String) -> String {
        text.lowercased()
            .folding(options: .diacriticInsensitive, locale: nil)
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{2018}", with: "'")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    private static func matches(_ phrases: [String], in normalized: String) -> Bool {
        phrases.contains { phrase in
            var searchRange = normalized.startIndex..<normalized.endIndex
            while let range = normalized.range(of: phrase, range: searchRange) {
                if isWordBoundary(before: range.lowerBound, in: normalized),
                   isWordBoundary(after: range.upperBound, in: normalized),
                   !isFollowedByFigurativeWord(phrase, at: range.upperBound, in: normalized) {
                    return true
                }
                searchRange = range.upperBound..<normalized.endIndex
            }
            return false
        }
    }

    private static func isFollowedByFigurativeWord(_ phrase: String, at index: String.Index, in text: String) -> Bool {
        // Only a space may separate them: "acabar con todo. El lunes…" still counts.
        let next = String(text[index...].drop { $0 == " " }.prefix { $0.isLetter })
        if let words = figurativeContinuations[phrase] {
            return words.contains(next)
        }
        if phrase.hasSuffix(" sin mi"), !next.isEmpty {
            return !spanishWordsAfterSinMi.contains(next)
        }
        return false
    }

    private static func isWordBoundary(before index: String.Index, in text: String) -> Bool {
        guard index > text.startIndex else { return true }
        return !text[text.index(before: index)].isLetter
    }

    private static func isWordBoundary(after index: String.Index, in text: String) -> Bool {
        guard index < text.endIndex else { return true }
        return !text[index].isLetter
    }
}
