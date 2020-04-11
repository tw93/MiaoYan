## 3. Code highlighting

FSNotes uses https://highlightjs.org, and currently supports code highlighting for 176 languages. This is perfect solution for programmers.

## Declaration examples

### Indentation code block

Shortcut – `command + ]`

	CREATE TABLE "topic" (
	    "id" serial NOT NULL PRIMARY KEY,
	    "forum_id" integer NOT NULL,
	    "subject" varchar(255) NOT NULL
	);
	ALTER TABLE "topic"
	ADD CONSTRAINT forum_id FOREIGN KEY ("forum_id")
	REFERENCES "forum" ("id");
	
	-- Initials
	insert into "topic" ("forum_id", "subject")
	values (2, 'D''artagnian');

###  Fenced code block

Shortcut – `control + command + c`

```swift
public static func getHighlighter() -> Highlightr? {
    if let instance = self.hl {
        return instance
    }
    
    guard let highlightr = Highlightr() else {
        return nil
    }
    
    highlightr.setTheme(to: "vs")
    self.hl = highlightr
    
    return self.hl
}
```
