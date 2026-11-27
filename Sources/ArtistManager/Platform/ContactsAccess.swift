import Contacts
import Foundation

/// Reads people from the Contacts app, only when the artist asks and only after macOS grants access.
/// Nothing is ever written back to Contacts.
enum ContactsAccess {
    enum Status { case notAsked, allowed, denied, unavailable }

    /// Contacts access needs the usage description in the packaged app's Info.plist.
    static var isAvailable: Bool {
        Bundle.main.object(forInfoDictionaryKey: "NSContactsUsageDescription") != nil
    }

    static var status: Status {
        guard isAvailable else { return .unavailable }
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .authorized: return .allowed
        case .notDetermined: return .notAsked
        case .denied, .restricted: return .denied
        @unknown default: return .allowed
        }
    }

    static func requestAccess() async -> Bool {
        guard isAvailable else { return false }
        return await withCheckedContinuation { continuation in
            CNContactStore().requestAccess(for: .contacts) { granted, _ in
                continuation.resume(returning: granted)
            }
        }
    }

    /// Everyone in Contacts with a name, company or email. Notes aren't read (macOS restricts them).
    static func fetchAll() async throws -> [Contact] {
        try await Task.detached(priority: .userInitiated) {
            let keys = [
                CNContactGivenNameKey, CNContactFamilyNameKey, CNContactOrganizationNameKey, CNContactJobTitleKey,
                CNContactEmailAddressesKey, CNContactPhoneNumbersKey, CNContactUrlAddressesKey, CNContactPostalAddressesKey,
                CNContactTypeKey
            ] as [CNKeyDescriptor]
            let request = CNContactFetchRequest(keysToFetch: keys)
            request.sortOrder = .userDefault
            var result: [Contact] = []
            try CNContactStore().enumerateContacts(with: request) { cn, _ in
                if let contact = map(cn) { result.append(contact) }
            }
            return result
        }.value
    }

    private static func map(_ cn: CNContact) -> Contact? {
        var c = Contact()
        if cn.contactType == .person {
            c.name = [cn.givenName, cn.familyName].filter { !$0.isBlank }.joined(separator: " ")
        }
        c.organization = cn.organizationName
        c.email = (cn.emailAddresses.first.map { $0.value as String }) ?? ""
        c.phone = cn.phoneNumbers.first?.value.stringValue ?? ""
        c.website = (cn.urlAddresses.first.map { $0.value as String }) ?? ""
        if let address = cn.postalAddresses.first?.value {
            c.location = [address.city, address.state].filter { !$0.isBlank }.joined(separator: ", ")
            if c.location.isBlank { c.location = address.country }
        }
        if !cn.jobTitle.isBlank {
            c.role = ContactCSV.role(from: cn.jobTitle) ?? .other
            c.notes = "Title: \(cn.jobTitle)"
        }
        guard !(c.name.isBlank && c.organization.isBlank && c.email.isBlank) else { return nil }
        return c
    }
}
