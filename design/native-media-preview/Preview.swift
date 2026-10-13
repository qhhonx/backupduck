import UIKit
import MapKit

// Independent interaction reference. No PhotoKit, backup engine, network consent,
// credentials, or production application data is used by this target.
private let canvas = UIColor(red: 245/255, green: 243/255, blue: 238/255, alpha: 1)
private let actionColor = UIColor(red: 22/255, green: 93/255, blue: 206/255, alpha: 1)
private let surface = UIColor(red: 29/255, green: 38/255, blue: 51/255, alpha: 1)
private let paleAction = UIColor(red: 140/255, green: 185/255, blue: 1, alpha: 1)
private func text(_ string: String, size: CGFloat = 17, weight: UIFont.Weight = .regular, color: UIColor = .label) -> UILabel {
    let label = UILabel(); label.text = string; label.font = .systemFont(ofSize: size, weight: weight); label.textColor = color
    label.numberOfLines = 0; return label
}
private func button(_ symbol: String, title: String, handler: @escaping () -> Void) -> UIButton {
    let b = UIButton(type: .system); b.setImage(UIImage(systemName: symbol), for: .normal)
    b.accessibilityLabel = title; b.addAction(UIAction { _ in handler() }, for: .touchUpInside); return b
}
private func spring(_ duration: TimeInterval = 0.36, velocity: CGFloat = 0, changes: @escaping () -> Void, completion: ((Bool) -> Void)? = nil) {
    if UIAccessibility.isReduceMotionEnabled { changes(); completion?(true); return }
    UIView.animate(withDuration: duration, delay: 0, usingSpringWithDamping: 0.92, initialSpringVelocity: velocity,
                   options: [.beginFromCurrentState, .allowUserInteraction], animations: changes, completion: completion)
}
private let pictures: [UIImage] = (0..<60).map { index in
    let size = CGSize(width: index % 7 == 0 ? 700 : 420, height: index % 7 == 0 ? 420 : 630)
    return UIGraphicsImageRenderer(size: size).image { renderer in
        let c = renderer.cgContext
        UIColor(hue: CGFloat(index % 12)/14+0.03, saturation: 0.22, brightness: 0.94, alpha: 1).setFill(); c.fill(CGRect(origin: .zero, size: size))
        UIColor(hue: CGFloat(index % 12)/14+0.05, saturation: 0.35, brightness: 0.65, alpha: 1).setFill()
        let hill = UIBezierPath(); hill.move(to: CGPoint(x: 0, y: size.height*0.55))
        hill.addCurve(to: CGPoint(x: size.width, y: size.height*0.54), controlPoint1: CGPoint(x: size.width*0.35, y: size.height*0.15), controlPoint2: CGPoint(x: size.width*0.6, y: size.height*0.76))
        hill.addLine(to: CGPoint(x: size.width,y: size.height)); hill.addLine(to: CGPoint(x: 0,y: size.height)); hill.close(); hill.fill()
        UIColor.white.withAlphaComponent(0.9).setFill(); c.fillEllipse(in: CGRect(x: size.width*0.69,y: size.height*0.16,width: 52,height: 52))
        let title = "\(index+1)" as NSString
        title.draw(at: CGPoint(x: 25,y: size.height-80), withAttributes: [.font: UIFont.systemFont(ofSize: 38,weight: .medium),.foregroundColor: UIColor.white])
    }
}
@main final class PreviewApp: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication, configurationForConnecting session: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: "Media reference",sessionRole: session.role)
        configuration.delegateClass = PreviewScene.self; return configuration
    }
}
final class PreviewScene: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let tab = UITabBarController()
        let library = LibraryController(); library.title = "照片图库"
        library.tabBarItem = UITabBarItem(title: "照片图库",image: UIImage(systemName: "photo.on.rectangle"),tag: 0)
        let settings = SettingsController(); settings.title = "备份设置"
        settings.tabBarItem = UITabBarItem(title: "设置",image: UIImage(systemName: "gearshape"),tag: 1)
        tab.viewControllers = [UINavigationController(rootViewController: library),UINavigationController(rootViewController: settings)]
        tab.tabBar.tintColor = actionColor
        let appearance = UITabBarAppearance(); appearance.configureWithOpaqueBackground(); appearance.backgroundColor = canvas
        tab.tabBar.standardAppearance = appearance; tab.tabBar.scrollEdgeAppearance = appearance
        let w = UIWindow(windowScene: windowScene); w.rootViewController = tab; w.makeKeyAndVisible(); window = w
    }
}
private final class PictureCell: UICollectionViewCell {
    let photo = UIImageView()
    let mark = UIImageView(image: UIImage(systemName: "checkmark.circle.fill"))
    override init(frame: CGRect) { super.init(frame: frame); photo.contentMode = .scaleAspectFill; photo.clipsToBounds = true; contentView.addSubview(photo); mark.tintColor = actionColor; mark.backgroundColor = .white; mark.layer.cornerRadius = 11.5; mark.clipsToBounds = true; mark.isHidden = true; contentView.addSubview(mark) }
    required init?(coder: NSCoder) { fatalError() }
    override func layoutSubviews() { super.layoutSubviews(); photo.frame = contentView.bounds; mark.frame = CGRect(x: bounds.width-29,y: bounds.height-29,width: 23,height: 23) }
}
private final class DateHeader: UICollectionReusableView {
    let title = text("",size: 17,weight: .semibold)
    override init(frame: CGRect) { super.init(frame: frame); backgroundColor = canvas; addSubview(title) }
    required init?(coder: NSCoder) { fatalError() }
    override func layoutSubviews() { super.layoutSubviews(); title.frame = bounds.insetBy(dx: 16,dy: 4) }
}
private final class LibraryController: UIViewController, UICollectionViewDataSource, UICollectionViewDelegate, UIViewControllerTransitioningDelegate {
    lazy var grid = UICollectionView(frame: .zero,collectionViewLayout: layout(columns: 3,mode: 0))
    let modes = UISegmentedControl(items: ["全部","日","月"])
    var columns = 3, mode = 0
    var pinchLayout: UICollectionViewTransitionLayout?
    var pinchColumns = 3, pinchAnchor = 0, pinchStart = CGPoint.zero, pinchEnd = CGPoint.zero
    var transition: PhotoTransition?
    override func viewDidLoad() {
        super.viewDidLoad(); view.backgroundColor = canvas; view.tintColor = actionColor
        navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(systemName: "line.3.horizontal.decrease.circle"),menu: UIMenu(title: "媒体类型",children: ["全部","照片","实况","视频","连拍"].map { name in UIAction(title: name,state: name == "全部" ? .on : .off) { _ in } }))
        navigationItem.prompt = "交互设计预览 · 示例图片"
        modes.selectedSegmentIndex = 0; modes.addAction(UIAction { [weak self] _ in self?.changeMode() },for: .valueChanged); view.addSubview(modes)
        grid.accessibilityIdentifier = "preview.grid"; grid.backgroundColor = canvas; grid.dataSource = self; grid.delegate = self
        grid.register(PictureCell.self,forCellWithReuseIdentifier: "photo"); grid.register(DateHeader.self,forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,withReuseIdentifier: "date")
        view.addSubview(grid); grid.addGestureRecognizer(UIPinchGestureRecognizer(target: self,action: #selector(pinch(_:))))
    }
    override func viewDidLayoutSubviews() { super.viewDidLayoutSubviews(); let top = view.safeAreaInsets.top
        modes.frame = CGRect(x: 16,y: top+6,width: view.bounds.width-32,height: 32)
        grid.frame = CGRect(x: 0,y: top+48,width: view.bounds.width,height: view.bounds.height-top-48-view.safeAreaInsets.bottom)
    }
    func layout(columns: Int,mode: Int) -> UICollectionViewFlowLayout {
        let l = UICollectionViewFlowLayout(); l.minimumInteritemSpacing = 2; l.minimumLineSpacing = 2
        let w = (view.bounds.width > 0 ? view.bounds.width : UIScreen.main.bounds.width)
        let s = floor((w-CGFloat(columns-1)*2)/CGFloat(columns)); l.itemSize = CGSize(width: s,height: s)
        l.headerReferenceSize = CGSize(width: w,height: mode == 0 ? 0 : 40); l.sectionHeadersPinToVisibleBounds = true
        return l
    }
    func numberOfSections(in collectionView: UICollectionView) -> Int { mode == 0 ? 1 : mode == 1 ? 6 : 2 }
    func collectionView(_ cv: UICollectionView,numberOfItemsInSection s: Int) -> Int { mode == 0 ? 60 : mode == 1 ? 10 : 30 }
    func index(_ p: IndexPath) -> Int { p.section*(mode == 0 ? 60 : mode == 1 ? 10 : 30)+p.item }
    func path(_ i: Int) -> IndexPath { let per = mode == 0 ? 60 : mode == 1 ? 10 : 30; return IndexPath(item: i%per,section: i/per) }
    func collectionView(_ cv: UICollectionView,cellForItemAt p: IndexPath) -> UICollectionViewCell {
        let c = cv.dequeueReusableCell(withReuseIdentifier: "photo",for: p) as! PictureCell; c.photo.image = pictures[index(p)]; c.accessibilityLabel = "示例照片 \(index(p)+1)"; return c
    }
    func collectionView(_ cv: UICollectionView,viewForSupplementaryElementOfKind kind: String,at p: IndexPath) -> UICollectionReusableView {
        let h = cv.dequeueReusableSupplementaryView(ofKind: kind,withReuseIdentifier: "date",for: p) as! DateHeader
        h.title.text = mode == 1 ? "10月\(12-p.section)日" : "2026年\(10-p.section)月"; return h
    }
    func changeMode() {
        let old = grid.indexPathsForVisibleItems.min() ?? IndexPath(item: 0,section: 0), anchor = index(old)
        mode = modes.selectedSegmentIndex; columns = mode == 2 ? 5 : 3
        // Calendar grouping changes the data sections. This reference deliberately
        // does not pretend this reload is the final calendar morph implementation.
        grid.setCollectionViewLayout(layout(columns: columns,mode: mode),animated: false); grid.reloadData(); grid.layoutIfNeeded()
        grid.scrollToItem(at: path(anchor),at: .top,animated: false)
    }
    @objc func pinch(_ g: UIPinchGestureRecognizer) {
        switch g.state {
        case .began:
            guard pinchLayout == nil else { return }
            pinchColumns = columns; let location = g.location(in: grid)
            let anchorPath = grid.indexPathForItem(at: location) ?? grid.indexPathsForVisibleItems.min() ?? IndexPath(item: 0,section: 0)
            pinchAnchor = index(anchorPath); pinchStart = grid.contentOffset
            let target = columns <= 3 ? 5 : 3, new = layout(columns: target,mode: mode)
            new.prepare(); pinchEnd = pinchStart
            let oldRect = grid.layoutAttributesForItem(at: anchorPath)?.frame ?? .zero
            pinchLayout = grid.startInteractiveTransition(to: new) { [weak self] finished,completed in
                guard let self else { return }; self.columns = completed ? target : self.pinchColumns; self.pinchLayout = nil
            }
            let targetRect = new.layoutAttributesForItem(at: anchorPath)?.frame ?? oldRect
            pinchEnd.y = max(0,min(max(0,new.collectionViewContentSize.height-grid.bounds.height),pinchStart.y+targetRect.midY-oldRect.midY))
        case .changed:
            guard let l = pinchLayout else { return }
            let p = max(0,min(1, pinchColumns <= 3 ? (1-g.scale)/0.4 : (g.scale-1)/0.6))
            l.transitionProgress = p; l.invalidateLayout(); grid.contentOffset.y = pinchStart.y+(pinchEnd.y-pinchStart.y)*p
        case .ended:
            guard let l = pinchLayout else { return }
            if l.transitionProgress > 0.45 { grid.finishInteractiveTransition() } else { grid.cancelInteractiveTransition() }
        case .cancelled,.failed: if pinchLayout != nil { grid.cancelInteractiveTransition() }
        default: break
        }
    }
    func collectionView(_ cv: UICollectionView,didSelectItemAt p: IndexPath) {
        let viewer = ViewerController(index: index(p)); viewer.modalPresentationStyle = .custom; viewer.transitioningDelegate = self
        viewer.source = { [weak self] i in
            guard let self else { return nil }; let p = self.path(i)
            if self.grid.cellForItem(at: p) == nil { self.grid.scrollToItem(at: p,at: .centeredVertically,animated: false); self.grid.layoutIfNeeded() }
            return (self.grid.cellForItem(at: p) as? PictureCell)?.photo
        }
        present(viewer,animated: true)
    }
    func animationController(forPresented presented: UIViewController,presenting: UIViewController,source: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        let a = PhotoTransition(presenting: true); transition = a; return a
    }
    func animationController(forDismissed dismissed: UIViewController) -> UIViewControllerAnimatedTransitioning? { PhotoTransition(presenting: false) }
}
private final class ZoomPage: UIScrollView, UIScrollViewDelegate {
    let image = UIImageView(); var changed: ((Bool) -> Void)?
    init(photo: UIImage) { super.init(frame: .zero); image.image = photo; image.contentMode = .scaleAspectFit; addSubview(image); delegate = self
        minimumZoomScale = 1; maximumZoomScale = 5; showsHorizontalScrollIndicator = false; showsVerticalScrollIndicator = false
        contentInsetAdjustmentBehavior = .never; panGestureRecognizer.isEnabled = false
        let double = UITapGestureRecognizer(target: self,action: #selector(doubleTap(_:))); double.numberOfTapsRequired = 2; addGestureRecognizer(double)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func layoutSubviews() { super.layoutSubviews(); if zoomScale == 1 {
        let size = image.image?.size ?? bounds.size
        let factor = min(bounds.width/max(1,size.width),bounds.height/max(1,size.height))
        image.frame = CGRect(x: bounds.midX-size.width*factor/2,y: bounds.midY-size.height*factor/2,width: size.width*factor,height: size.height*factor); contentSize = bounds.size
    } }
    func viewForZooming(in scrollView: UIScrollView) -> UIView? { image }
    func scrollViewDidZoom(_ scrollView: UIScrollView) { panGestureRecognizer.isEnabled = zoomScale > 1.01; changed?(zoomScale > 1.01) }
    @objc func doubleTap(_ g: UITapGestureRecognizer) {
        if zoomScale > 1.01 { setZoomScale(1,animated: true) }
        else { let p = g.location(in: image); zoom(to: CGRect(x: p.x-bounds.width/5,y: p.y-bounds.height/5,width: bounds.width/2.5,height: bounds.height/2.5),animated: true) }
    }
}
/// A bounded filmstrip layout. Only the settled current item expands; dragging
/// uses a uniform pitch so scrub position has one unambiguous owner.
@MainActor final class MediaFilmstripLayout: UICollectionViewLayout {
    let pitch: CGFloat = 27
    var current = 0, expansion: CGFloat = 1, aspect: CGFloat = 1
    var count: Int { collectionView?.numberOfItems(inSection: 0) ?? 0 }
    var selectedWidth: CGFloat { 24 + (min(52,max(26,44*aspect))-24)*expansion }
    var extra: CGFloat { selectedWidth-24+16*expansion }
    func center(_ index: Int) -> CGFloat {
        CGFloat(index)*pitch + (index == current ? 8*expansion+selectedWidth/2 : 12+(index > current ? extra : 0))
    }
    func nearest(_ x: CGFloat) -> Int {
        max(0,min(count-1,Int(round((x-12)/pitch))))
    }
    override var collectionViewContentSize: CGSize {
        CGSize(width: max(0,CGFloat(count)*pitch-3+extra),height: collectionView?.bounds.height ?? 44)
    }
    override func layoutAttributesForItem(at path: IndexPath) -> UICollectionViewLayoutAttributes? {
        guard let collectionView, path.item < count else { return nil }
        let selected = path.item == current
        let width: CGFloat = selected ? selectedWidth : 24
        let height: CGFloat = selected ? 36+8*expansion : 36
        let attributes = UICollectionViewLayoutAttributes(forCellWith: path)
        attributes.frame = CGRect(x: center(path.item)-width/2,y: (collectionView.bounds.height-height)/2,width: width,height: height)
        return attributes
    }
    override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        guard count > 0 else { return [] }
        let first = max(0,Int(floor((rect.minX-extra)/pitch))-2)
        let last = min(count-1,Int(ceil(rect.maxX/pitch))+2)
        guard first <= last else { return [] }
        return (first...last).compactMap { layoutAttributesForItem(at: IndexPath(item: $0,section: 0)) }.filter { $0.frame.intersects(rect) }
    }
    override func shouldInvalidateLayout(forBoundsChange bounds: CGRect) -> Bool { bounds.size != collectionView?.bounds.size }
}

private final class ViewerController: UIViewController, UIScrollViewDelegate, UICollectionViewDataSource, UICollectionViewDelegate, UIGestureRecognizerDelegate {
    var index: Int, source: ((Int) -> UIImageView?)?
    let stage = UIView(), pager = UIScrollView(), header = UIView(), footer = UIView(), titleLabel = text("",size: 15,weight: .semibold,color: .white)
    let status = text("",size: 12,color: .lightGray), progress = UIProgressView(progressViewStyle: .default)
    let stripLayout = MediaFilmstripLayout()
    lazy var strip = UICollectionView(frame: .zero,collectionViewLayout: stripLayout)
    var pages: [ZoomPage] = [], suppress = false, chrome = true, infoHeight: CGFloat = 0, infoStart: CGFloat = 0, gestureKind = 0
    var hasConsent = false, consent: UIView?, loadingTask: DispatchWorkItem?, infoAnimator: UIViewPropertyAnimator?
    let info = UIScrollView(), infoBody = UIView()
    init(index: Int) { self.index = index; super.init(nibName: nil,bundle: nil) }
    required init?(coder: NSCoder) { fatalError() }
    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }
    override func viewDidLoad() {
        super.viewDidLoad(); view.backgroundColor = .black; view.addSubview(stage); stage.addSubview(pager)
        pager.accessibilityIdentifier = "preview.pager"; pager.isPagingEnabled = true; pager.showsHorizontalScrollIndicator = false; pager.delegate = self; pager.decelerationRate = .fast
        pager.contentInsetAdjustmentBehavior = .never; view.addSubview(header); view.addSubview(footer)
        let close = button("chevron.left",title: "返回图库") { [weak self] in self?.close() }; close.tintColor = .white; close.frame = CGRect(x: 8,y: 0,width: 44,height: 44); header.addSubview(close)
        header.addSubview(titleLabel); header.addSubview(status); header.addSubview(progress); progress.tintColor = paleAction; progress.isHidden = true
        strip.accessibilityIdentifier = "preview.filmstrip"; strip.backgroundColor = .clear; strip.showsHorizontalScrollIndicator = false; strip.dataSource = self; strip.delegate = self
        strip.register(PictureCell.self,forCellWithReuseIdentifier: "strip"); footer.addSubview(strip)
        info.accessibilityIdentifier = "preview.info"; view.addSubview(info); info.backgroundColor = surface; info.layer.cornerRadius = 20; info.layer.maskedCorners = [.layerMinXMinYCorner,.layerMaxXMinYCorner]; info.addSubview(infoBody)
        let up = UIPanGestureRecognizer(target: self,action: #selector(vertical(_:))); up.delegate = self; stage.addGestureRecognizer(up)
        let handle = UIView(); handle.tag = 5; handle.backgroundColor = .white.withAlphaComponent(0.35); handle.layer.cornerRadius = 2; infoBody.addSubview(handle)
        let dismissInfo = button("xmark",title: "关闭信息") { [weak self] in self?.setInfo(open: false) }; dismissInfo.tintColor = paleAction; dismissInfo.tag = 6; infoBody.addSubview(dismissInfo)
        let date = text("2026年10月11日",size: 24,weight: .semibold,color: .white); date.frame = CGRect(x: 20,y: 50,width: 320,height: 36); infoBody.addSubview(date)
        let file = text("IMG_0042.HEIC\n12 MP · 3024 × 4032 · 2.4 MB\niPhone · 26 mm · ƒ/1.8 · ISO 100",size: 15,color: .white); file.frame = CGRect(x: 20,y: 100,width: 320,height: 88); infoBody.addSubview(file)
        let mapTitle = text("拍摄位置 · 示例位置",size: 15,color: .white); mapTitle.frame = CGRect(x: 20,y: 208,width: 320,height: 28); infoBody.addSubview(mapTitle)
        let map = MKMapView(frame: CGRect(x: 20,y: 246,width: 320,height: 160)); map.tag = 8; map.isUserInteractionEnabled = false; map.layer.cornerRadius = 12; map.clipsToBounds = true
        map.setRegion(MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 37.3349,longitude: -122.0090),span: MKCoordinateSpan(latitudeDelta: 0.014,longitudeDelta: 0.014)),animated: false); infoBody.addSubview(map)
        let note = text("信息为设计示例，未读取真实照片。",size: 12,color: .lightGray); note.frame = CGRect(x: 20,y: 428,width: 320,height: 30); infoBody.addSubview(note)
        let handlePan = UIPanGestureRecognizer(target: self,action: #selector(infoPan(_:))); infoBody.addGestureRecognizer(handlePan); handlePan.delegate = self
        reloadPages(); updateHeader()
    }
    override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); if index == 2 && !hasConsent { showConsent() } }
    override func viewDidLayoutSubviews() { super.viewDidLayoutSubviews(); layoutMedia(); if let c = consent { layoutConsent(c) } }
    func layoutMedia() {
        let b = view.bounds, top = view.safeAreaInsets.top, bottom = view.safeAreaInsets.bottom
        header.frame = CGRect(x: 0,y: top,width: b.width,height: 74); titleLabel.frame = CGRect(x: 58,y: 3,width: b.width-116,height: 26); titleLabel.textAlignment = .center
        status.frame = CGRect(x: 58,y: 30,width: b.width-116,height: 22); status.textAlignment = .center
        header.viewWithTag(7)?.frame = CGRect(x: b.width-52,y: 0,width: 44,height: 44)
        progress.frame = CGRect(x: b.width/2-65,y: 58,width: 130,height: 2)
        footer.frame = CGRect(x: 0,y: b.height-bottom-64,width: b.width,height: 64)
        strip.frame = footer.bounds.insetBy(dx: 16,dy: 10); strip.contentInset = UIEdgeInsets(top: 0,left: strip.bounds.width/2-15,bottom: 0,right: strip.bounds.width/2-15)
        stage.frame = CGRect(x: 0,y: top+74,width: b.width,height: max(100,b.height-top-74-bottom-64-infoHeight))
        pager.frame = stage.bounds; suppress = true
        pager.contentSize = CGSize(width: stage.bounds.width*3,height: stage.bounds.height)
        for (i,p) in pages.enumerated() { p.frame = CGRect(x: CGFloat(i)*stage.bounds.width,y: 0,width: stage.bounds.width,height: stage.bounds.height) }
        if !pager.isDragging && !pager.isDecelerating { pager.contentOffset.x = stage.bounds.width }
        suppress = false
        info.frame = CGRect(x: 0,y: b.height-infoHeight,width: b.width,height: infoHeight)
        infoBody.frame = CGRect(x: 0,y: 0,width: b.width,height: 485); info.contentSize = infoBody.bounds.size
        infoBody.viewWithTag(5)?.frame = CGRect(x: b.width/2-18,y: 10,width: 36,height: 4)
        infoBody.viewWithTag(6)?.frame = CGRect(x: b.width-56,y: 20,width: 44,height: 44)
        infoBody.viewWithTag(8)?.frame.size.width = b.width-40
        header.alpha = chrome && infoHeight < 50 ? 1 : 0; footer.alpha = chrome && infoHeight < 50 ? 1 : 0
    }
    func reloadPages(updateStrip: Bool = true) {
        for p in pages { p.removeFromSuperview() }; pages = []
        for i in -1...1 { let actual = max(0,min(pictures.count-1,index+i)), p = ZoomPage(photo: pictures[actual]); p.changed = { [weak self] zoomed in self?.pager.isScrollEnabled = !zoomed }; pager.addSubview(p); pages.append(p) }
        pager.isScrollEnabled = true; layoutMedia(); stripLayout.current = index; stripLayout.invalidateLayout(); if updateStrip { strip.reloadData(); centerStrip(animated: false) }
    }
    func updateHeader() { titleLabel.text = "2026年10月11日"; status.text = "14:\(String(format: "%02d",index)) · 示例 \(index+1)" }
    func go(_ i: Int, fromStrip: Bool = false) { let target = max(0,min(pictures.count-1,i)); guard target != index else { return }; index = target; loadingTask?.cancel(); progress.isHidden = true; reloadPages(updateStrip: !fromStrip); updateHeader() }
    func scrollViewDidScroll(_ s: UIScrollView) {
        guard !suppress else { return }
        if s === pager {
            if !strip.isDragging && !strip.isDecelerating { suppress = true; strip.contentOffset.x = stripLayout.center(index)-strip.bounds.width/2+(s.contentOffset.x/max(1,s.bounds.width)-1)*stripLayout.pitch; suppress = false }
        } else if s === strip, s.isDragging || s.isDecelerating {
            let next = stripLayout.nearest(s.contentOffset.x+s.bounds.width/2); if next != index {
                let offset = s.contentOffset; go(next,fromStrip: true); suppress = true; s.contentOffset = offset; suppress = false
            }
        }
    }
    func scrollViewWillBeginDragging(_ scroll: UIScrollView) {
        stripLayout.expansion = 0; stripLayout.invalidateLayout(); strip.layoutIfNeeded()
        if scroll === strip { centerStripOffset() }
    }
    func centerStripOffset() {
        suppress = true; strip.contentOffset.x = stripLayout.center(index)-strip.bounds.width/2; suppress = false
    }
    func scrollViewDidEndDecelerating(_ s: UIScrollView) { settle(s) }
    func scrollViewDidEndDragging(_ s: UIScrollView,willDecelerate decelerate: Bool) { if !decelerate { settle(s) } }
    func settle(_ s: UIScrollView) {
        if s === pager { go(index+Int(round(s.contentOffset.x/max(1,s.bounds.width)))-1); suppress = true; s.contentOffset.x = s.bounds.width; suppress = false }
        stripLayout.expansion = 1; stripLayout.invalidateLayout(); strip.layoutIfNeeded(); centerStrip(animated: true)
    }
    func centerStrip(animated: Bool) { guard !strip.isDragging && !strip.isDecelerating else { return }; suppress = true; strip.setContentOffset(CGPoint(x: stripLayout.center(index)-strip.bounds.width/2,y: 0),animated: animated); suppress = false }
    func collectionView(_ cv: UICollectionView,numberOfItemsInSection section: Int) -> Int { pictures.count }
    func collectionView(_ cv: UICollectionView,cellForItemAt p: IndexPath) -> UICollectionViewCell {
        let c = cv.dequeueReusableCell(withReuseIdentifier: "strip",for: p) as! PictureCell; c.photo.image = pictures[p.item]; c.layer.cornerRadius = 4; c.clipsToBounds = true; c.layer.borderWidth = p.item == index ? 2 : 0; c.layer.borderColor = UIColor.white.cgColor; return c
    }
    func collectionView(_ cv: UICollectionView,didSelectItemAt p: IndexPath) { go(p.item) }
    func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
        guard consent == nil, !pager.isDragging, !pager.isDecelerating, pages.count == 3, pages[1].zoomScale <= 1.01 else { return false }
        if let p = g as? UIPanGestureRecognizer { let v = p.velocity(in: view); return abs(v.y)>abs(v.x)*1.4 }
        return true
    }
    func gestureRecognizer(_ g: UIGestureRecognizer,shouldReceive touch: UITouch) -> Bool {
        if touch.view is UIControl { return false }
        if g.view === infoBody { return touch.location(in: infoBody).y < 70 }
        return true
    }
    @objc func vertical(_ g: UIPanGestureRecognizer) {
        let t = g.translation(in: view), v = g.velocity(in: view)
        switch g.state {
        case .began: gestureKind = t.y >= 0 && v.y >= 0 ? 1 : 2; infoStart = infoHeight; infoAnimator?.stopAnimation(true)
        case .changed:
            if gestureKind == 1 { pages[1].image.transform = CGAffineTransform(translationX: t.x,y: max(0,t.y)).scaledBy(x: max(0.65,1-max(0,t.y)/1000),y: max(0.65,1-max(0,t.y)/1000)); view.backgroundColor = UIColor.black.withAlphaComponent(max(0.1,1-max(0,t.y)/300)); header.alpha = max(0,1-t.y/80); footer.alpha = header.alpha }
            else { infoHeight = max(0,min(view.bounds.height*0.72,infoStart-t.y)); layoutMedia() }
        case .ended,.cancelled:
            if gestureKind == 1 {
                if g.state == .ended && (t.y > 12 && v.y > -120) { close() }
                else { spring(velocity: abs(v.y)/700) { self.pages[1].image.transform = .identity; self.view.backgroundColor = .black; self.layoutMedia() } }
            } else { setInfo(open: g.state == .ended && (-t.y+(-v.y)*0.12)>100) }
            gestureKind = 0
        default: break
        }
    }
    @objc func infoPan(_ g: UIPanGestureRecognizer) {
        switch g.state {
        case .began: infoStart = infoHeight; infoAnimator?.stopAnimation(true)
        case .changed: infoHeight = max(0,min(view.bounds.height*0.72,infoStart-g.translation(in: view).y)); layoutMedia()
        case .ended,.cancelled: setInfo(open: g.state == .ended && infoHeight-g.velocity(in: view).y*0.12>150)
        default: break
        }
    }
    func setInfo(open: Bool) {
        guard consent == nil else { return }; for p in pages { p.setZoomScale(1,animated: false) }
        infoHeight = open ? min(500,view.bounds.height*0.45) : 0
        infoAnimator?.stopAnimation(true); infoAnimator = UIViewPropertyAnimator(duration: 0.38,dampingRatio: 0.92) { self.layoutMedia() }; infoAnimator?.startAnimation()
    }
    func close() { guard consent == nil else { return }; loadingTask?.cancel(); dismiss(animated: true) }
    func showConsent() {
        guard consent == nil else { return }
        let sheet = ConsentController { [weak self] allow in self?.endConsent(allow: allow) }
        sheet.modalPresentationStyle = .pageSheet
        if let presentation = sheet.sheetPresentationController {
            presentation.detents = [.custom(identifier: .init("content")) { _ in 310 }, .large()]
            presentation.prefersGrabberVisible = true
            presentation.preferredCornerRadius = 20
        }
        sheet.dismissed = { [weak self] in self?.consent = nil }
        sheet.presentationController?.delegate = sheet
        consent = sheet.view
        present(sheet,animated: true)
    }
    func layoutConsent(_ dim: UIView) {}
    func endConsent(allow: Bool) {
        dismiss(animated: true); consent = nil; hasConsent = allow
        guard allow else { status.text = "仅本地预览 · 示例"; return }; status.text = "正在加载清晰预览…"; progress.isHidden = false; progress.progress = 0.1
        let task = DispatchWorkItem { [weak self] in self?.progress.isHidden = true; self?.updateHeader() }; loadingTask = task
        UIView.animate(withDuration: 1.4) { self.progress.setProgress(1,animated: true) }; DispatchQueue.main.asyncAfter(deadline: .now()+1.8,execute: task)
    }
    var transitionImage: UIImageView { pages[1].image }
}
private final class ConsentController: UIViewController, UIAdaptivePresentationControllerDelegate {
    var dismissed: (() -> Void)?
    func presentationControllerDidDismiss(_ controller: UIPresentationController) { dismissed?() }
    let decision: (Bool) -> Void
    init(decision: @escaping (Bool) -> Void) { self.decision = decision; super.init(nibName: nil,bundle: nil) }
    required init?(coder: NSCoder) { fatalError() }
    override func viewDidLoad() {
        super.viewDidLoad(); view.backgroundColor = surface
        let heading = text("从 iCloud 加载预览",size: 22,weight: .bold,color: .white)
        heading.tag = 1; view.addSubview(heading)
        let note = text("允许加载照片和视频的清晰预览，不会开始备份。你可以在设置中更改。",size: 16,color: .lightGray)
        note.tag = 2; view.addSubview(note)
        for (tag,label,allow) in [(3,"暂不加载",false),(4,"允许加载",true)] {
            let action = UIButton(type: .system); action.tag = tag; action.setTitle(label,for: .normal)
            action.titleLabel?.font = .systemFont(ofSize: 16,weight: allow ? .semibold : .regular)
            action.tintColor = allow ? surface : paleAction; action.backgroundColor = allow ? paleAction : surface
            action.layer.cornerRadius = 10; action.layer.borderWidth = 1
            action.layer.borderColor = (allow ? paleAction : UIColor.gray.withAlphaComponent(0.4)).cgColor
            action.addAction(UIAction { [weak self] _ in self?.decision(allow) },for: .touchUpInside); view.addSubview(action)
        }
    }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews(); let w = view.bounds.width, bottom = view.bounds.height-view.safeAreaInsets.bottom
        view.viewWithTag(1)?.frame = CGRect(x: 20,y: 30,width: w-40,height: 36)
        view.viewWithTag(2)?.frame = CGRect(x: 20,y: 94,width: w-40,height: 72)
        let bw = (w-52)/2
        view.viewWithTag(3)?.frame = CGRect(x: 20,y: bottom-72,width: bw,height: 52)
        view.viewWithTag(4)?.frame = CGRect(x: 32+bw,y: bottom-72,width: bw,height: 52)
    }
}
private final class PhotoTransition: NSObject, UIViewControllerAnimatedTransitioning {
    let presenting: Bool
    init(presenting: Bool) { self.presenting = presenting }
    func transitionDuration(using context: UIViewControllerContextTransitioning?) -> TimeInterval { UIAccessibility.isReduceMotionEnabled ? 0.12 : 0.38 }
    func animateTransition(using context: UIViewControllerContextTransitioning) {
        guard let viewer = context.viewController(forKey: presenting ? .to : .from) as? ViewerController else { context.completeTransition(false); return }
        let container = context.containerView; if presenting { viewer.view.frame = context.finalFrame(for: viewer); container.addSubview(viewer.view) }
        viewer.view.layoutIfNeeded()
        guard let thumb = viewer.source?(viewer.index) else { UIView.animate(withDuration: 0.18,animations: { viewer.view.alpha = self.presenting ? 1 : 0 }) { _ in context.completeTransition(!context.transitionWasCancelled) }; return }
        let photo = viewer.transitionImage, proxy = UIImageView(image: pictures[viewer.index]); proxy.contentMode = .scaleAspectFill; proxy.clipsToBounds = true
        let size = pictures[viewer.index].size, bounds = photo.bounds
        let scale = min(bounds.width/size.width,bounds.height/size.height)
        let fitted = CGRect(x: bounds.midX-size.width*scale/2,y: bounds.midY-size.height*scale/2,width: size.width*scale,height: size.height*scale)
        let big = photo.convert(fitted,to: container), small = thumb.convert(thumb.bounds,to: container)
        proxy.frame = presenting ? small : big; container.addSubview(proxy); photo.isHidden = true; thumb.isHidden = true
        viewer.view.alpha = presenting ? 0 : 1
        spring(transitionDuration(using: context)) { proxy.frame = self.presenting ? big : small; viewer.view.alpha = self.presenting ? 1 : 0 } completion: { _ in
            photo.isHidden = false; thumb.isHidden = false; proxy.removeFromSuperview(); context.completeTransition(!context.transitionWasCancelled)
        }
    }
}
private final class SettingsController: UITableViewController {
    override func viewDidLoad() { super.viewDidLoad(); tableView.backgroundColor = canvas; tableView.register(UITableViewCell.self,forCellReuseIdentifier: "row") }
    override func tableView(_ tableView: UITableView,numberOfRowsInSection section: Int) -> Int { 3 }
    override func tableView(_ tableView: UITableView,cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let c = tableView.dequeueReusableCell(withIdentifier: "row",for: indexPath); var config = c.defaultContentConfiguration();
        if indexPath.row == 2 {
            config.text = "从 iCloud 加载预览"; config.secondaryText = "浏览时加载清晰预览，可能使用蜂窝数据；不会开始备份。关闭后仅加载本机可用的预览。"
            c.contentConfiguration = config; c.accessoryView = UISwitch(); return c
        }
        c.accessoryView = nil; config.text = indexPath.row == 0 ? "媒体类型" : "指定相簿"; config.secondaryText = indexPath.row == 0 ? "全部类型" : "全部相簿"; config.secondaryText = indexPath.row == 0 ? "全部类型" : "全部相簿"; c.contentConfiguration = config; c.accessoryType = .disclosureIndicator; return c
    }
    override func tableView(_ tableView: UITableView,didSelectRowAt indexPath: IndexPath) {
        guard indexPath.row < 2 else { return }
        navigationController?.pushViewController(indexPath.row == 0 ? TypesController() : AlbumsController(),animated: true)
    }
}
private final class TypesController: UITableViewController {
    var selected = Set(0..<4)
    override func viewDidLoad() { super.viewDidLoad(); title = "媒体类型"; tableView.backgroundColor = canvas; tableView.register(UITableViewCell.self,forCellReuseIdentifier: "row") }
    override func tableView(_ tableView: UITableView,numberOfRowsInSection section: Int) -> Int { 4 }
    override func tableView(_ tableView: UITableView,cellForRowAt p: IndexPath) -> UITableViewCell {
        let c = tableView.dequeueReusableCell(withIdentifier: "row",for: p); c.textLabel?.text = ["照片","实况","视频","连拍"][p.row]; c.selectionStyle = .none; c.accessoryType = selected.contains(p.row) ? .checkmark : .none; return c
    }
    override func tableView(_ tableView: UITableView,didSelectRowAt p: IndexPath) { if selected.contains(p.row) { selected.remove(p.row) } else { selected.insert(p.row) }; tableView.cellForRow(at: p)?.accessoryType = selected.contains(p.row) ? .checkmark : .none; tableView.deselectRow(at: p,animated: false) }
}
private final class AlbumCell: UICollectionViewCell {
    let photo = UIImageView(), name = text("",size: 13,weight: .medium), count = text("",size: 13,color: .secondaryLabel), check = UIImageView(image: UIImage(systemName: "checkmark.circle.fill"))
    override init(frame: CGRect) { super.init(frame: frame); photo.contentMode = .scaleAspectFill; photo.clipsToBounds = true; photo.layer.cornerRadius = 12
        [photo,name,count,check].forEach { contentView.addSubview($0) }; check.tintColor = actionColor; check.backgroundColor = .white; check.layer.cornerRadius = 11.5; check.clipsToBounds = true }
    required init?(coder: NSCoder) { fatalError() }
    override func layoutSubviews() { super.layoutSubviews(); photo.frame = CGRect(x: 0,y: 0,width: bounds.width,height: bounds.height-52); name.frame = CGRect(x: 0,y: bounds.height-46,width: bounds.width,height: 24); count.frame = CGRect(x: 0,y: bounds.height-22,width: bounds.width,height: 20); check.frame = CGRect(x: bounds.width-29,y: photo.frame.maxY-29,width: 23,height: 23) }
}
private final class AlbumsController: UICollectionViewController, UISearchResultsUpdating {
    var selected = Set<Int>(), visible = Array(0..<80)
    init() { let l = UICollectionViewFlowLayout(); l.minimumInteritemSpacing = 12; l.minimumLineSpacing = 16; l.sectionInset = UIEdgeInsets(top: 16,left: 16,bottom: 16,right: 16); super.init(collectionViewLayout: l) }
    required init?(coder: NSCoder) { fatalError() }
    override func viewDidLoad() { super.viewDidLoad(); title = "指定相簿"; collectionView.backgroundColor = canvas; collectionView.register(AlbumCell.self,forCellWithReuseIdentifier: "album")
        let search = UISearchController(searchResultsController: nil); search.searchResultsUpdater = self; search.obscuresBackgroundDuringPresentation = false; search.searchBar.placeholder = "搜索相簿"; navigationItem.searchController = search; navigationItem.hidesSearchBarWhenScrolling = false
    }
    override func viewDidLayoutSubviews() { super.viewDidLayoutSubviews(); let side = (view.bounds.width-56)/3; (collectionViewLayout as? UICollectionViewFlowLayout)?.itemSize = CGSize(width: side,height: side+52) }
    func updateSearchResults(for searchController: UISearchController) { let q = searchController.searchBar.text ?? ""; visible = (0..<80).filter { q.isEmpty || "相簿 \($0+1)".contains(q) }; collectionView.reloadData() }
    override func collectionView(_ cv: UICollectionView,numberOfItemsInSection section: Int) -> Int { visible.count }
    override func collectionView(_ cv: UICollectionView,cellForItemAt p: IndexPath) -> UICollectionViewCell {
        let c = cv.dequeueReusableCell(withReuseIdentifier: "album",for: p) as! AlbumCell, i = visible[p.item]
        c.photo.image = pictures[i%pictures.count]; c.name.text = "相簿 \(i+1)"; c.count.text = "\((i+1)*37) 个项目"; c.check.isHidden = !selected.contains(i); c.photo.alpha = selected.contains(i) ? 0.72 : 1; c.accessibilityIdentifier = "reference.album.\(i)"; c.isAccessibilityElement = true; c.accessibilityTraits = selected.contains(i) ? [.button,.selected] : .button; return c
    }
    override func collectionView(_ cv: UICollectionView,didSelectItemAt p: IndexPath) { let i = visible[p.item]; if selected.contains(i) { selected.remove(i) } else { selected.insert(i) }; if let cell = collectionView.cellForItem(at: p) as? AlbumCell { cell.check.isHidden = !selected.contains(i); cell.photo.alpha = selected.contains(i) ? 0.72 : 1 }; navigationItem.prompt = selected.isEmpty ? "全部相簿" : "\(selected.count) 个指定相簿" }
}
