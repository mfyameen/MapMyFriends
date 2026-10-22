//
//  EmptyMapCardView.swift
//  MapMyFriends
//

import UIKit

/// Card over the map when no contact has an address, so an empty map doesn't look broken.
/// With limited Contacts access it explains why and offers to share more contacts.
final class EmptyMapCardView: UIView {

    /// Called when the user taps "Share More Contacts".
    var onShareMoreContacts: (() -> Void)?

    private let titleLabel = UILabel()
    private let messageLabel = UILabel()
    private let shareMoreButton = UIButton(configuration: .borderedProminent())

    override init(frame: CGRect) {
        super.init(frame: frame)

        let background = UIVisualEffectView(effect: UIBlurEffect(style: .systemThickMaterial))
        background.translatesAutoresizingMaskIntoConstraints = false
        background.layer.cornerRadius = 16
        background.clipsToBounds = true
        addSubview(background)

        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.12
        layer.shadowRadius = 10
        layer.shadowOffset = CGSize(width: 0, height: 2)

        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.numberOfLines = 0
        titleLabel.textAlignment = .center

        messageLabel.font = .preferredFont(forTextStyle: .subheadline)
        messageLabel.adjustsFontForContentSizeCategory = true
        messageLabel.textColor = .secondaryLabel
        messageLabel.numberOfLines = 0
        messageLabel.textAlignment = .center

        shareMoreButton.configuration?.title = "Share More Contacts"
        shareMoreButton.configuration?.cornerStyle = .capsule
        shareMoreButton.addAction(UIAction { [weak self] _ in self?.onShareMoreContacts?() }, for: .primaryActionTriggered)

        let stack = UIStackView(arrangedSubviews: [titleLabel, messageLabel, shareMoreButton])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 8
        stack.setCustomSpacing(14, after: messageLabel)
        stack.translatesAutoresizingMaskIntoConstraints = false
        background.contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            background.topAnchor.constraint(equalTo: topAnchor),
            background.bottomAnchor.constraint(equalTo: bottomAnchor),
            background.leadingAnchor.constraint(equalTo: leadingAnchor),
            background.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: background.contentView.topAnchor, constant: 18),
            stack.bottomAnchor.constraint(equalTo: background.contentView.bottomAnchor, constant: -18),
            stack.leadingAnchor.constraint(equalTo: background.contentView.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: background.contentView.trailingAnchor, constant: -20),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(limitedAccess: Bool) {
        if limitedAccess {
            titleLabel.text = "No addresses in the contacts you shared"
            messageLabel.text = "Map My Friends can only see the contacts you chose to share, and none of them have an address."
        } else {
            titleLabel.text = "None of your contacts have an address yet"
            messageLabel.text = "Add an address to a contact in the Contacts app and they'll appear on the map."
        }
        shareMoreButton.isHidden = !limitedAccess
    }
}
