import Testing
@testable import JournalFoundation

struct JournalRiskClassifierSpanishTests {

    @Test func directSelfHarmLanguageIsHighRisk() {
        for text in [
            "Anoche pensé en el suicidio.",
            "Hay días que quiero morirme.",
            "Me quiero morir.",
            "A veces pienso en matarme",
            "Quiero hacerme daño otra vez",
            "Volví a autolesionarme",
            "Las autolesiones empezaron en enero",
            "Pensé en quitarme la vida",
            "No quiero vivir así",
            "Solo quiero acabar con todo.",
            "Quiero acabar con todo esto",
        ] {
            #expect(JournalRiskClassifier.level(for: text) == .highRiskExcluded, "\(text)")
        }
    }

    @Test func indirectWordingIsHighRisk() {
        for text in [
            "Todos estarían mejor sin mí.",
            "Sería más fácil si yo no estuviera",
            "Quiero desaparecer para siempre",
            "No hay razón para vivir así",
            "Mi familia estaría mejor sin mí, de verdad",
        ] {
            #expect(JournalRiskClassifier.level(for: text) == .highRiskExcluded, "\(text)")
        }
    }

    @Test func matchingIgnoresAccentsAndCase() {
        #expect(JournalRiskClassifier.level(for: "quiero hacerme dano") == .highRiskExcluded)
        #expect(JournalRiskClassifier.level(for: "ESTARIAN MEJOR SIN MI") == .highRiskExcluded)
        #expect(JournalRiskClassifier.level(for: "Pense en el SUICIDIO") == .highRiskExcluded)
        #expect(JournalRiskClassifier.level(for: "Tuve un ataque de panico") == .mildDistress)
    }

    @Test func figuresOfSpeechAreNotFlagged() {
        for text in [
            "Me muero de risa con este libro",
            "Me mata el tráfico de los lunes",
            "Me muero de ganas de verte",
            "Quiero desaparecer en un buen libro este finde",
            "Hoy quiero acabar con todo el papeleo",
            "Por fin terminé con todo lo pendiente y quiero terminar con todo el correo",
            "El equipo estaría mejor sin mi jefe",
        ] {
            #expect(JournalRiskClassifier.level(for: text) == .none, "\(text)")
        }
    }

    @Test func tiredFiguresOfSpeechStayMild() {
        #expect(JournalRiskClassifier.level(for: "Estoy muerta de cansancio") == .mildDistress)
        #expect(JournalRiskClassifier.level(for: "Llegué muerto de cansancio") == .mildDistress)
    }

    @Test func hopelessnessIsModerate() {
        for text in [
            "Me siento sin esperanza",
            "Ya no puedo más",
            "No aguanto más esta semana",
            "Nada tiene sentido últimamente",
            "Nadie se daría cuenta",
        ] {
            #expect(JournalRiskClassifier.level(for: text) == .moderateConcern, "\(text)")
        }
    }

    @Test func distressIsMild() {
        for text in [
            "Estoy agotada",
            "Terminé agotado",
            "El trabajo me tiene abrumada",
            "Me sentí abrumado en la reunión",
            "Tuve un ataque de pánico antes de la llamada",
        ] {
            #expect(JournalRiskClassifier.level(for: text) == .mildDistress, "\(text)")
        }
    }

    @Test func mixedLanguageJournalsAreScreened() {
        #expect(JournalRiskClassifier.level(for: "Long day at work. Quiero morirme.") == .highRiskExcluded)
        #expect(JournalRiskClassifier.level(for: "Hoy fue largo. I want to die.") == .highRiskExcluded)
        #expect(JournalRiskClassifier.level(for: "Me muero de ganas, I'm dying to see the movie") == .none)
        #expect(JournalRiskClassifier.level(for: "Cena con Maya. Lunch with Sam.") == .none)
    }

    @Test func englishPhrasesDontMatchInsideSpanishWords() {
        // "pánico" folds to "panico"; the English "panic" must not match it as
        // a whole word, so the level comes from the Spanish list alone.
        #expect(JournalRiskClassifier.level(for: "Sentí pánico") == .mildDistress)
        #expect(JournalRiskClassifier.level(for: "Fue un día panicoso") == .none)
    }

    @Test func standardPolicyMapsSpanishLevels() {
        #expect(JournalRiskClassifier.responseMode(for: "Quiero hacerme daño") == .supportOnly)
        #expect(JournalRiskClassifier.responseMode(for: "No puedo más") == .gentle)
        #expect(JournalRiskClassifier.responseMode(for: "Comida con Maya") == .normal)
    }
}
