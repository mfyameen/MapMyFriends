//
//  ClusterAnnotationView.swift
//  MapMyFriends
//

import MapKit

class ClusterAnnotationView: MKAnnotationView {

    private let countLabel = UILabel()
    private let circleView = UIView()

    override init(annotation: (any MKAnnotation)?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)

        frame = CGRect(x: 0, y: 0, width: 40, height: 40)

        circleView.frame = bounds
        circleView.backgroundColor = .systemBlue
        circleView.layer.cornerRadius = 20
        circleView.clipsToBounds = true
        addSubview(circleView)

        countLabel.frame = bounds
        countLabel.textAlignment = .center
        countLabel.textColor = .white
        countLabel.font = .boldSystemFont(ofSize: 15)
        addSubview(countLabel)
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var annotation: (any MKAnnotation)? {
        didSet {
            if let cluster = annotation as? MKClusterAnnotation {
                countLabel.text = "\(cluster.memberAnnotations.count)"
            }
        }
    }
}
