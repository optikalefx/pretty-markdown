// Lightweight syntax highlighter for fenced code blocks. Uses the fence's
// language-* class when present, otherwise sniffs the language heuristically.
(function() {
  function esc(s) {
    return s.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');
  }
  const KW = {
    swift: new Set('import class struct enum protocol extension func var let if else guard switch case default for while repeat in return break continue throws throw rethrows try catch async await static final public private internal fileprivate open mutating lazy override required convenience init deinit subscript get set willSet didSet self super nil true false typealias associatedtype where some any nonisolated isolated actor'.split(' ')),
    javascript: new Set('const let var function return if else for while do switch case default break continue class extends super import export from as async await try catch finally throw new this typeof instanceof void delete in of null undefined true false yield get set static'.split(' ')),
    typescript: new Set('const let var function return if else for while do switch case default break continue class extends implements interface type enum namespace import export from as async await try catch finally throw new this typeof instanceof void delete in of null undefined true false yield get set static private public protected readonly abstract declare keyof infer never unknown any string number boolean object symbol'.split(' ')),
    python: new Set('def class import from as return if elif else for while in not and or is None True False try except finally raise with yield lambda pass break continue global nonlocal async await del assert'.split(' ')),
    go: new Set('package import func var const type struct interface if else for range return break continue switch case default go defer select chan map nil true false error'.split(' ')),
    sql: new Set('SELECT FROM WHERE JOIN LEFT RIGHT INNER OUTER FULL CROSS ON AS AND OR NOT IN IS NULL ORDER BY GROUP HAVING LIMIT OFFSET INSERT INTO VALUES UPDATE SET DELETE CREATE TABLE INDEX DROP ALTER ADD COLUMN PRIMARY KEY FOREIGN REFERENCES UNIQUE DEFAULT COUNT SUM AVG MIN MAX DISTINCT UNION ALL CASE WHEN THEN END ELSE WITH RETURNING'.split(' ')),
    bash: new Set('if then else elif fi for do done while until case esac function return exit echo local export source set unset shift true false'.split(' ')),
  };
  function detect(code) {
    if (/\b(SELECT|INSERT INTO|UPDATE\s+\w+\s+SET|CREATE TABLE)\b/i.test(code)) return 'sql';
    if (/^\s*package\s+\w+|:=\s*/m.test(code) && /\bfunc\b/.test(code)) return 'go';
    if (/\bfunc\s+\w+|\bguard\b|\bnil\b/.test(code) && /->|\.self\b|@MainActor/.test(code)) return 'swift';
    if (/\bfunc\s+\w+|\bvar\s+\w+\s*[:=]|\blet\s+\w+\s*[:=]/.test(code) && /\bguard\b|\bnil\b|->/.test(code)) return 'swift';
    if (/\bdef\s+\w+\s*\(|^from\s+\w+\s+import\b|^\s*import\s+\w+\s*$/m.test(code)) return 'python';
    if (/:\s*(string|number|boolean|void|never|any)\b|interface\s+\w+\s*\{|<[A-Z]\w*>/.test(code)) return 'typescript';
    if (/\bfunction\s+\w+|\bconst\s+\w+\s*=|\brequire\s*\(|=>\s*[{(]/.test(code)) return 'javascript';
    if (/^\s*#!(\/bin\/(bash|sh)|\/usr\/bin\/env\s+bash)/m.test(code)) return 'bash';
    return null;
  }
  function tokenize(code, lang) {
    const isSQL = lang === 'sql';
    const kw = KW[lang] || new Set();
    let out = '', i = 0;
    while (i < code.length) {
      const c = code[i];
      if (c === '/' && code[i+1] === '*') {
        const e = code.indexOf('*/', i+2); const end = e < 0 ? code.length : e+2;
        out += '<span class=cm>' + esc(code.slice(i,end)) + '</span>'; i = end; continue;
      }
      if ((c === '/' && code[i+1] === '/') || (c === '#' && (lang==='python'||lang==='bash'))) {
        const e = code.indexOf('\n', i); const end = e < 0 ? code.length : e;
        out += '<span class=cm>' + esc(code.slice(i,end)) + '</span>'; i = end; continue;
      }
      if (c === '-' && code[i+1] === '-' && isSQL) {
        const e = code.indexOf('\n', i); const end = e < 0 ? code.length : e;
        out += '<span class=cm>' + esc(code.slice(i,end)) + '</span>'; i = end; continue;
      }
      if (c === '"' || c === "'" || (c === '`' && (lang==='javascript'||lang==='typescript'))) {
        const q = c; let j = i+1;
        while (j < code.length) { if (code[j]==='\\') {j+=2;continue;} if (code[j]===q){j++;break;} j++; }
        out += '<span class=s>' + esc(code.slice(i,j)) + '</span>'; i = j; continue;
      }
      if (/[0-9]/.test(c) && (i===0||!/\w/.test(code[i-1]))) {
        let j = i; while (j<code.length && /[0-9a-fA-F._xXbBoOpPlLeEuU]/.test(code[j])) j++;
        out += '<span class=n>' + esc(code.slice(i,j)) + '</span>'; i = j; continue;
      }
      if (/[a-zA-Z_$]/.test(c)) {
        let j = i; while (j<code.length && /[\w$]/.test(code[j])) j++;
        const w = code.slice(i,j);
        if (kw.has(isSQL ? w.toUpperCase() : w)) out += '<span class=kw>' + esc(w) + '</span>';
        else if (/^[A-Z]/.test(w) && !isSQL) out += '<span class=tp>' + esc(w) + '</span>';
        else out += esc(w);
        i = j; continue;
      }
      out += esc(c); i++;
    }
    return out;
  }
  document.querySelectorAll('pre code').forEach(el => {
    const m = el.className.match(/language-(\w+)/);
    const lang = m ? m[1] : detect(el.textContent);
    if (lang) el.innerHTML = tokenize(el.textContent, lang);
  });
})();
