import Cocoa

extension ViewController: NSSharingServicePickerDelegate {
    func sharingServicePicker(_ sharingServicePicker: NSSharingServicePicker, sharingServicesForItems items: [Any], proposedSharingServices proposedServices: [NSSharingService]) -> [NSSharingService] {
        
        guard let image = NSImage(named: "copy.png") else {
            return proposedServices
        }
        
        var share = proposedServices
        let titlePlain = NSLocalizedString("Copy Plain Text", comment: "")
        let plainText = NSSharingService(title: titlePlain, image: image, alternateImage: image, handler: {
            self.saveTextAtClipboard()
        })
        share.insert(plainText, at: 0)

        let titleHTML = NSLocalizedString("Copy HTML", comment: "")
        let html = NSSharingService(title: titleHTML, image: image, alternateImage: image, handler: {
            self.saveHtmlAtClipboard()
        })
        share.insert(html, at: 1)
        
        return share
    }
}
