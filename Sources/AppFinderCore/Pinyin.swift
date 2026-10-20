import Foundation

/// Pinyin for names that contain Han characters, so that `jisuanqi` and `jsq` find 计算器.
///
/// Each Han character goes through the system's Mandarin transliteration with diacritics
/// stripped, and every syllable starts a word of the key. Initials therefore need no key of their
/// own: the matcher's word start bonus ranks `jsq` on `ji suan qi` as highly as a prefix.
///
/// The system picks one reading per character without looking at its neighbours (音乐 comes out
/// as `yin le`, 银行 as `yin xing`), so the characters in `alternateReadings` add a key for each
/// of their other readings, up to `maxVariants` keys per name.
public enum Pinyin {
    static let maxVariants = 8

    /// Readings besides the one the system gives, for polyphonic characters common in app names.
    static let alternateReadings: [Character: [String]] = [
        "乐": ["le", "yue"], "行": ["xing", "hang"], "长": ["chang", "zhang"], "重": ["zhong", "chong"],
        "还": ["hai", "huan"], "调": ["tiao", "diao"], "传": ["chuan", "zhuan"], "藏": ["cang", "zang"],
        "朝": ["chao", "zhao"], "和": ["he", "huo"], "降": ["jiang", "xiang"], "觉": ["jue", "jiao"],
        "弹": ["tan", "dan"], "了": ["le", "liao"], "便": ["bian", "pian"], "参": ["can", "shen"],
        "差": ["cha", "chai"], "大": ["da", "dai"], "地": ["di", "de"], "得": ["de", "dei"],
        "都": ["du", "dou"], "给": ["gei", "ji"], "系": ["xi", "ji"], "解": ["jie", "xie"],
        "落": ["luo", "la"], "模": ["mo", "mu"], "强": ["qiang", "jiang"], "省": ["sheng", "xing"],
        "识": ["shi", "zhi"], "属": ["shu", "zhu"], "提": ["ti", "di"], "着": ["zhe", "zhao", "zhuo"],
        "区": ["qu", "ou"], "单": ["dan", "shan"], "查": ["cha", "zha"], "曾": ["ceng", "zeng"],
        "期": ["qi", "ji"], "盛": ["sheng", "cheng"], "厦": ["xia", "sha"], "率": ["lv", "shuai"],
        "画": ["hua"], "绿": ["lv", "lu"], "女": ["nv", "nu"], "旅": ["lv", "lu"], "律": ["lv", "lu"],
    ]

    /// The pinyin keys of a name, empty when the name has no Han character.
    public static func keys(for name: String) -> [SearchKey] {
        guard containsHan(name) else { return [] }
        var choices: [[String]] = []
        for character in name {
            guard character.unicodeScalars.contains(where: \.isHan) else {
                choices.append([String(character)])
                continue
            }
            var readings: [String] = []
            if let latin = String(character).applyingTransform(.mandarinToLatin, reverse: false),
               let plain = latin.applyingTransform(.stripDiacritics, reverse: false) {
                readings.append(plain.trimmingCharacters(in: .whitespaces))
            }
            for reading in alternateReadings[character] ?? [] where !readings.contains(reading) {
                readings.append(reading)
            }
            // Spaces around a syllable make it a word of its own in the key.
            choices.append(readings.isEmpty ? [String(character)] : readings.map { " \($0) " })
        }
        var variants = [""]
        for options in choices {
            var next: [String] = []
            for variant in variants {
                for option in options where next.count < maxVariants {
                    next.append(variant + option)
                }
            }
            variants = next
        }
        return variants.map(SearchKey.init).filter { !$0.isEmpty }
    }

    public static func containsHan(_ text: String) -> Bool {
        text.unicodeScalars.contains(where: \.isHan)
    }
}
