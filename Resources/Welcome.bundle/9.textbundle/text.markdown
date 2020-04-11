## 9. Containers

What are containers? A 'container' is a holder for your files. A container holds text and other assets used in one note. Of course, you can choose to store notes without containers at all. Open Preferences -> General -> Containers and select "None". Notes will be stored in plain text, Markdown or RTF.

I recommend to use Text Bundle and Encrypted Text Bundles for sensitive data. Read on.

### Text Bundle container

File extension – `.textbundle`

TextBundle – file format aims to provide a more seamless user experience when exchanging plain text files, like Markdown or RTF, between applications. http://textbundle.org

For example, a Markdown file may contain references to external images. When sending such a file from a Markdown editor to a previewer, users will have to explicitly permit access to every single image file. This is where TextBundle comes handy. TextBundle brings the convenience back - by bundling the Markdown text and all referenced images into a single file.

### Encrypted Text Bundle container

File extension – `.etp`.

Encrypted Text Bundle is used for notes encryption. It is encrypted Text Pack (a zipped Text Bundle) and encrypted with RNCryptor. RNCryptor is cross-platform data format and there are many implementations. Under the hood, we have:

AES-256 encryption
CBC mode
Password stretching with PBKDF2
Password salting
Random IV
Encrypt-then-hash HMAC
Open and cross platform

You can decrypt any FSNotes note with Python or Ruby, JS, etc. (full list you can find here)
Unzip and have fun with usual Text Bundle.
