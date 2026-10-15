import Foundation

extension Party {
    /// Legacy keys are a reading fallback only; never inject IDs into an old frozen record.
    public func participantKey() -> String { id.ifBlank("legacy-\(role.rawValue)") }
    public func signerName() -> String { representedBy.ifBlank(name) }
}

extension HandoverProtocol {
    public func partyFor(signature: Signature) -> Party? {
        parties.first { signature.participantId.isBlank ? $0.role == signature.role : $0.participantKey() == signature.participantId }
    }

    public func signatureFor(party: Party, plane: Plane = .record) -> Signature? {
        signatures.first {
            $0.plane == plane && ($0.participantId.isBlank
                ? $0.role == party.role && party.id.isBlank
                : $0.participantId == party.participantKey())
        }
    }

    /// An explicitly saved empty reservation replaces old ink's reservation.
    public func reservationFor(party: Party) -> String {
        details.reservations[party.participantKey()] ?? pendingRecordReservations[party.role] ?? signatureFor(party: party)?.reservation ?? ""
    }

    public func copyDeliveredTo(_ party: Party) -> Bool {
        deliveryReceipts.contains {
            $0.participantId.isBlank ? party.id.isBlank && $0.role == party.role : $0.participantId == party.participantKey()
        }
    }

    /// Keep all contractual parties; a new inspection requires authority to be checked again.
    public func partiesForExit(role: Role, identity: SessionIdentity) -> [Party] {
        parties.map { party in
            var next = party
            next.representedBy = ""
            next.authority = ""
            if role == .tenant, party.role == role,
               party.name.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(identity.fullName) == .orderedSame {
                next.address = [identity.addressLine, identity.placeLine].filter { !$0.isBlank }.joined(separator: ", ")
                next.phone = identity.phone.ifBlank(party.phone)
            } else if role == .landlord, party.role == role, !identity.company.isBlank,
                      parties.filter({ $0.role == .landlord }).count == 1 || party.agency == identity.company {
                next.agency = identity.company
                next.representedBy = identity.fullName
                next.phone = identity.phone.ifBlank(party.phone)
            }
            return next
        }
    }

    public func allPhotoEvidence() -> [PhotoEvidence] {
        defects.flatMap(\.photoEvidence) + objects.flatMap(\.photoEvidence) +
            details.roomPhotos.entries.flatMap(\.value) + details.readings.flatMap(\.photos)
    }

    public func allPhotoFiles() -> [String] {
        (defects.flatMap { $0.photoFiles() } + objects.flatMap { $0.photoFiles() } + allPhotoEvidence().map(\.file)).distinct()
    }
}
