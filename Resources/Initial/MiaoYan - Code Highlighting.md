## Code highlighting

Supports 176 languages

## Autodetect

### SQL

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

## Manual declaration examples

### Swift

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

### CSS 

	article, aside, details, figcaption, figure, footer, header, hgroup,
	nav, section, summary {
	    display: block;
	}
	
	audio, canvas, video {
	    display: inline-block;
	}
	
	audio:not([controls]) {
	    display: none;
	    height: 0;
	}
	
	[hidden] {
	    display: none;
	}
