local M = {}

--- Romaji → katakana conversion for the MeCab reading-index mode.
--- Hepburn + Kunrei variants; small tsu via doubled consonants; trailing
--- consonant fragments become a "row constraint" on the next reading char
--- (same acceptance model as migemo's trailing-consonant expansion).

---@type table<string, string>
local TABLE = {
  a = "ア", i = "イ", u = "ウ", e = "エ", o = "オ",
  ka = "カ", ki = "キ", ku = "ク", ke = "ケ", ko = "コ",
  ga = "ガ", gi = "ギ", gu = "グ", ge = "ゲ", go = "ゴ",
  kya = "キャ", kyu = "キュ", kyo = "キョ",
  gya = "ギャ", gyu = "ギュ", gyo = "ギョ",
  sa = "サ", si = "シ", shi = "シ", su = "ス", se = "セ", so = "ソ",
  za = "ザ", zi = "ジ", ji = "ジ", zu = "ズ", ze = "ゼ", zo = "ゾ",
  sha = "シャ", sya = "シャ", shu = "シュ", syu = "シュ",
  sho = "ショ", syo = "ショ", she = "シェ",
  ja = "ジャ", jya = "ジャ", zya = "ジャ", ju = "ジュ", jyu = "ジュ",
  zyu = "ジュ", jo = "ジョ", jyo = "ジョ", zyo = "ジョ", je = "ジェ",
  ta = "タ", ti = "チ", chi = "チ", tu = "ツ", tsu = "ツ", te = "テ", to = "ト",
  da = "ダ", di = "ヂ", du = "ヅ", de = "デ", ["do"] = "ド",
  cha = "チャ", tya = "チャ", chu = "チュ", tyu = "チュ",
  cho = "チョ", tyo = "チョ", che = "チェ",
  dya = "ヂャ", dyu = "ヂュ", dyo = "ヂョ",
  tsa = "ツァ", tsi = "ツィ", tse = "ツェ", tso = "ツォ",
  thi = "ティ", dhi = "ディ", thu = "テュ", dhu = "デュ",
  na = "ナ", ni = "ニ", nu = "ヌ", ne = "ネ", no = "ノ",
  nya = "ニャ", nyu = "ニュ", nyo = "ニョ",
  ha = "ハ", hi = "ヒ", hu = "フ", fu = "フ", he = "ヘ", ho = "ホ",
  ba = "バ", bi = "ビ", bu = "ブ", be = "ベ", bo = "ボ",
  pa = "パ", pi = "ピ", pu = "プ", pe = "ペ", po = "ポ",
  hya = "ヒャ", hyu = "ヒュ", hyo = "ヒョ",
  bya = "ビャ", byu = "ビュ", byo = "ビョ",
  pya = "ピャ", pyu = "ピュ", pyo = "ピョ",
  fa = "ファ", fi = "フィ", fe = "フェ", fo = "フォ",
  ma = "マ", mi = "ミ", mu = "ム", me = "メ", mo = "モ",
  mya = "ミャ", myu = "ミュ", myo = "ミョ",
  ya = "ヤ", yu = "ユ", yo = "ヨ",
  ra = "ラ", ri = "リ", ru = "ル", re = "レ", ro = "ロ",
  rya = "リャ", ryu = "リュ", ryo = "リョ",
  wa = "ワ", wo = "ヲ", wi = "ウィ", we = "ウェ",
  va = "ヴァ", vi = "ヴィ", vu = "ヴ", ve = "ヴェ", vo = "ヴォ",
  la = "ァ", xa = "ァ", li = "ィ", xi = "ィ", lu = "ゥ", xu = "ゥ",
  le = "ェ", xe = "ェ", lo = "ォ", xo = "ォ",
  lya = "ャ", xya = "ャ", lyu = "ュ", xyu = "ュ", lyo = "ョ", xyo = "ョ",
  ltu = "ッ", xtu = "ッ", ltsu = "ッ",
  ["-"] = "ー",
}

--- Allowed next reading chars for a trailing romaji fragment.
---@type table<string, string>
local PENDING = {
  k = "カキクケコ", ky = "キ", g = "ガギグゲゴ", gy = "ギ",
  s = "サシスセソ", sh = "シ", sy = "シ",
  z = "ザジズゼゾ", zy = "ジ", j = "ジ", jy = "ジ",
  t = "タチツテト", ts = "ツ", ty = "チ", ch = "チ", c = "チ", th = "テ",
  d = "ダヂヅデド", dy = "ヂ", dh = "デ",
  n = "ナニヌネノン", ny = "ニ",
  h = "ハヒフヘホ", hy = "ヒ", f = "フ",
  b = "バビブベボ", by = "ビ", p = "パピプペポ", py = "ピ",
  m = "マミムメモ", my = "ミ",
  y = "ヤユヨ", r = "ラリルレロ", ry = "リ",
  w = "ワヲウ", v = "ヴ",
  l = "ァィゥェォャュョッ", x = "ァィゥェォャュョッ",
}

--- Convert romaji to katakana.
--- Returns nil when the input contains anything that cannot be part of a
--- Japanese reading (the caller should fall back to literal/migemo layers).
---@param input string
---@return string|nil kana  converted katakana (may be "" for pure fragments)
---@return string|nil pending  allowed chars for the NEXT reading char, if the
---        input ends in a consonant fragment
function M.to_kana(input)
  input = input:lower()
  local out = {}
  local i, n = 1, #input
  while i <= n do
    local c = input:sub(i, i)
    local nx = input:sub(i + 1, i + 1)

    -- Doubled consonant → ッ (except n/l/x which have their own rules)
    if c == nx and c:match("[bcdfghjkmpqrstvwz]") then
      out[#out + 1] = "ッ"
      i = i + 1
    elseif c == "n" and nx == "n" then
      -- nn → ン (IME convention; "nnna" → ンナ)
      out[#out + 1] = "ン"
      i = i + 2
    elseif c == "n" and nx == "'" then
      out[#out + 1] = "ン"
      i = i + 2
    else
      local matched = false
      for len = math.min(4, n - i + 1), 1, -1 do
        local seg = input:sub(i, i + len - 1)
        if TABLE[seg] then
          out[#out + 1] = TABLE[seg]
          i = i + len
          matched = true
          break
        end
      end
      if not matched then
        if c == "n" and nx ~= "" and not nx:match("[aiueoy]") then
          -- n before another consonant → ン
          out[#out + 1] = "ン"
          i = i + 1
        else
          -- Unconverted tail: trailing fragment or non-Japanese input
          local rest = input:sub(i)
          if PENDING[rest] then
            return table.concat(out), PENDING[rest]
          end
          return nil, nil
        end
      end
    end
  end
  return table.concat(out), nil
end

return M
