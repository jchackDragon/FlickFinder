//
//  ViewController.swift
//  FlickFinder
//
//  Created by Jarrod Parkes on 11/5/15.
//  Copyright © 2015 Udacity. All rights reserved.
//

import UIKit

// MARK: - ViewController: UIViewController

class ViewController: UIViewController {
    
    // MARK: Properties
    
    var keyboardOnScreen = false
    
    // MARK: Outlets
    
    @IBOutlet weak var photoImageView: UIImageView!
    @IBOutlet weak var photoTitleLabel: UILabel!
    @IBOutlet weak var phraseTextField: UITextField!
    @IBOutlet weak var phraseSearchButton: UIButton!
    @IBOutlet weak var latitudeTextField: UITextField!
    @IBOutlet weak var longitudeTextField: UITextField!
    @IBOutlet weak var latLonSearchButton: UIButton!
    
    // MARK: Life Cycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        phraseTextField.delegate = self
        latitudeTextField.delegate = self
        longitudeTextField.delegate = self
        subscribeToNotification(.UIKeyboardWillShow, selector: #selector(keyboardWillShow))
        subscribeToNotification(.UIKeyboardWillHide, selector: #selector(keyboardWillHide))
        subscribeToNotification(.UIKeyboardDidShow, selector: #selector(keyboardDidShow))
        subscribeToNotification(.UIKeyboardDidHide, selector: #selector(keyboardDidHide))
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        unsubscribeFromAllNotifications()
    }
    
    // MARK: Search Actions
    
    @IBAction func searchByPhrase(_ sender: AnyObject) {

        userDidTapView(self)
        setUIEnabled(false)
        
        if !phraseTextField.text!.isEmpty {
            photoTitleLabel.text = "Searching..."
            // TODO: Set necessary parameters!
            let methodParameters = [
                Constants.FlickrParameterKeys.SafeSearch: Constants.FlickrParameterValues.UseSafeSearch
                ,Constants.FlickrParameterKeys.Text: phraseTextField.text!
                ,Constants.FlickrParameterKeys.Extras: Constants.FlickrParameterValues.MediumURL
                ,Constants.FlickrParameterKeys.APIKey: Constants.FlickrParameterValues.APIKey
                ,Constants.FlickrParameterKeys.Method: Constants.FlickrParameterValues.SearchMethod
                ,Constants.FlickrParameterKeys.Format: Constants.FlickrParameterValues.ResponseFormat
                ,Constants.FlickrParameterKeys.NoJSONCallback: Constants.FlickrParameterValues.DisableJSONCallback
            ]
            
            displayImageFromFlickrBySearch(methodParameters as [String:AnyObject])
        } else {
            setUIEnabled(true)
            photoTitleLabel.text = "Phrase Empty."
        }
    }
    
    @IBAction func searchByLatLon(_ sender: AnyObject) {

        userDidTapView(self)
        setUIEnabled(false)
        
        if isTextFieldValid(latitudeTextField, forRange: Constants.Flickr.SearchLatRange) && isTextFieldValid(longitudeTextField, forRange: Constants.Flickr.SearchLonRange) {
            photoTitleLabel.text = "Searching..."
            // TODO: Set necessary parameters!
            let methodParameters = [
                Constants.FlickrParameterKeys.SafeSearch: Constants.FlickrParameterValues.UseSafeSearch
                ,Constants.FlickrParameterKeys.BoundingBox: bboxString()
                ,Constants.FlickrParameterKeys.Extras: Constants.FlickrParameterValues.MediumURL
                ,Constants.FlickrParameterKeys.APIKey: Constants.FlickrParameterValues.APIKey
                ,Constants.FlickrParameterKeys.Method: Constants.FlickrParameterValues.SearchMethod
                ,Constants.FlickrParameterKeys.Format: Constants.FlickrParameterValues.ResponseFormat
                ,Constants.FlickrParameterKeys.NoJSONCallback: Constants.FlickrParameterValues.DisableJSONCallback
            ]
            displayImageFromFlickrBySearch(methodParameters as [String:AnyObject])
        }
        else {
            setUIEnabled(true)
            photoTitleLabel.text = "Lat should be [-90, 90].\nLon should be [-180, 180]."
        }
    }
    
    // MARK: Flickr API
    
    private func bboxString() -> String{
        if let latitude = Double(latitudeTextField.text!),
            let longitude = Double(longitudeTextField.text!){
        
            let minLongitude = max(longitude - Constants.Flickr.SearchBBoxHalfWidth, Constants.Flickr.SearchLonRange.0)
            let minLatitude  = max(latitude  - Constants.Flickr.SearchBBoxHalfHeight, Constants.Flickr.SearchLatRange.0)
            let maxLongitude = min(longitude + Constants.Flickr.SearchBBoxHalfWidth, Constants.Flickr.SearchLonRange.1)
            let maxLatitude  = min(latitude  + Constants.Flickr.SearchBBoxHalfHeight, Constants.Flickr.SearchLonRange.1)
        
        return"\(minLongitude),\(minLatitude),\(maxLongitude),\(maxLatitude)"
        
        }else{
        
            return "0,0,0,0"
        }
    }
    
    private func displayImageFromFlickrBySearch(_ methodParameters: [String: AnyObject]) {
       
        let session = URLSession.shared
        let request  = URLRequest(url: flickrURLFromParameters(methodParameters))
        let task     = session.dataTask(with: request){(data, request, error) in
    
            print("Request: url: \(request?.url)")
            
            func displayError(_ error:String){
                print("URL request error \(request?.url)")
                print(error)
                
                performUIUpdatesOnMain {
                    self.setUIEnabled(true)
                    self.photoTitleLabel.text = "No Image found"
                    self.photoImageView = nil
                }
            }
            
            guard (error == nil) else{
                displayError("The was a error in your request \(error)")
                return
            }
            
            guard let statusCode = (request as? HTTPURLResponse)?.statusCode, statusCode >= 200 && statusCode <= 299 else {
                displayError("The server response with status code other than 2xx")
                return
            }
            
            guard let data = data else{
                displayError("The request not returned any data")
                return
            }
            
            let parsedData:[String:AnyObject]!
            
            do{
                parsedData = try? JSONSerialization.jsonObject(with: data, options: .allowFragments) as! [String:AnyObject]
            }catch{
                displayError("Cannot parse data to a JSON: \(data)")
            }
            
            guard let stat = parsedData[Constants.FlickrResponseKeys.Status] as? String, stat == Constants.FlickrResponseValues.OKStatus else{
                displayError("Flickr return a error. See the error code and message in \(parsedData)")
                return
            }
            
            guard let photos = parsedData[Constants.FlickrResponseKeys.Photos] as? [String:AnyObject] else{
                displayError("Cannot find keys '\(Constants.FlickrResponseKeys.Photos)' in \(parsedData)")
                return
            }
            
            
            guard let totalPages = photos[Constants.FlickrResponseKeys.Pages] as? Int else{
                displayError("Cannot find key '\(Constants.FlickrResponseKeys.Pages)' in \(photos)")
                return
            }
            
            let pageLimit = min(totalPages, 40)
            let randomPage = Int(arc4random_uniform(UInt32(pageLimit))) + 1
            
            self.displayImageFromFlickrBySearch(methodParameters: methodParameters, withPageNumber: randomPage)
            
        }
        
        task.resume()
        
    }
    
    
    private func displayImageFromFlickrBySearch( methodParameters: [String: AnyObject], withPageNumber page: Int) {
        
        var methodParameters = methodParameters
        methodParameters[Constants.FlickrParameterKeys.Page] = page as AnyObject
        
        let session = URLSession.shared
        let request  = URLRequest(url: flickrURLFromParameters(methodParameters))
        let task     = session.dataTask(with: request){(data, request, error) in
            
            
            print("Request: url: \(request?.url)")
            func displayError(_ error:String){
                print("URL request error \(request?.url)")
                print(error)
                
                performUIUpdatesOnMain {
                    self.setUIEnabled(true)
                    self.photoTitleLabel.text = "No Image found"
                    self.photoImageView = nil
                }
            }
            
            guard (error == nil) else{
                displayError("The was a error in your request \(error)")
                return
            }
            
            guard let statusCode = (request as? HTTPURLResponse)?.statusCode, statusCode >= 200 && statusCode <= 299 else {
                displayError("The server response with status code other than 2xx")
                return
            }
            
            guard let data = data else{
                displayError("The request not returned any data")
                return
            }
            
            let parsedData:[String:AnyObject]!
            
            do{
                parsedData = try? JSONSerialization.jsonObject(with: data, options: .allowFragments) as! [String:AnyObject]
            }catch{
                displayError("Cannot parse data to a JSON: \(data)")
            }
            
            guard let stat = parsedData[Constants.FlickrResponseKeys.Status] as? String, stat == Constants.FlickrResponseValues.OKStatus else{
                displayError("Flickr return a error. See the error code and message in \(parsedData)")
                return
            }
            
            guard let photos = parsedData[Constants.FlickrResponseKeys.Photos] as? [String:AnyObject], let photo = photos[Constants.FlickrResponseKeys.Photo] as? [[String:AnyObject]] else{
                displayError("Cannot find keys '\(Constants.FlickrResponseKeys.Photos)' and '\(Constants.FlickrResponseKeys.Photo)' in \(parsedData)")
                return
            }
            
            if(photo.count == 0){
                displayError("No photo returned in \(photos)")
            }else{
                
             let ranIndex = Int(arc4random_uniform(UInt32(photo.count)))
             let randomItem = photo[ranIndex]
             
             
             let title = randomItem["title"] as? String
             
             guard let urlString = randomItem["url_m"] as? String, let imageURL = URL(string: urlString) else{
                displayError("Cannot find key 'url_m' in \(randomItem)")
                return
             }
             
             if let data = try?Data(contentsOf:imageURL){
                performUIUpdatesOnMain {
                    self.photoImageView?.image = UIImage(data: data)
                    self.photoTitleLabel?.text = title ?? "(untitle)"
                    self.setUIEnabled(true)
             }
                
            }
        }
        }
        
        task.resume()
        
    }
    // MARK: Helper for Creating a URL from Parameters
    
    private func flickrURLFromParameters(_ parameters: [String: AnyObject]) -> URL {
        
        var components = URLComponents()
        components.scheme = Constants.Flickr.APIScheme
        components.host = Constants.Flickr.APIHost
        components.path = Constants.Flickr.APIPath
        components.queryItems = [URLQueryItem]()
        
        for (key, value) in parameters {
            let queryItem = URLQueryItem(name: key, value: "\(value)")
            components.queryItems!.append(queryItem)
        }
        
        return components.url!
    }
}

// MARK: - ViewController: UITextFieldDelegate

extension ViewController: UITextFieldDelegate {
    
    // MARK: UITextFieldDelegate
    
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
    
    // MARK: Show/Hide Keyboard
    
    func keyboardWillShow(_ notification: Notification) {
        if !keyboardOnScreen {
            view.frame.origin.y -= keyboardHeight(notification)
        }
    }
    
    func keyboardWillHide(_ notification: Notification) {
        if keyboardOnScreen {
            view.frame.origin.y += keyboardHeight(notification)
        }
    }
    
    func keyboardDidShow(_ notification: Notification) {
        keyboardOnScreen = true
    }
    
    func keyboardDidHide(_ notification: Notification) {
        keyboardOnScreen = false
    }
    
    func keyboardHeight(_ notification: Notification) -> CGFloat {
        let userInfo = (notification as NSNotification).userInfo
        let keyboardSize = userInfo![UIKeyboardFrameEndUserInfoKey] as! NSValue
        return keyboardSize.cgRectValue.height
    }
    
    func resignIfFirstResponder(_ textField: UITextField) {
        if textField.isFirstResponder {
            textField.resignFirstResponder()
        }
    }
    
    @IBAction func userDidTapView(_ sender: AnyObject) {
        resignIfFirstResponder(phraseTextField)
        resignIfFirstResponder(latitudeTextField)
        resignIfFirstResponder(longitudeTextField)
    }
    
    // MARK: TextField Validation
    
    func isTextFieldValid(_ textField: UITextField, forRange: (Double, Double)) -> Bool {
        if let value = Double(textField.text!), !textField.text!.isEmpty {
            return isValueInRange(value, min: forRange.0, max: forRange.1)
        } else {
            return false
        }
    }
    
    func isValueInRange(_ value: Double, min: Double, max: Double) -> Bool {
        return !(value < min || value > max)
    }
}

// MARK: - ViewController (Configure UI)

private extension ViewController {
    
     func setUIEnabled(_ enabled: Bool) {
        photoTitleLabel.isEnabled = enabled
        phraseTextField.isEnabled = enabled
        latitudeTextField.isEnabled = enabled
        longitudeTextField.isEnabled = enabled
        phraseSearchButton.isEnabled = enabled
        latLonSearchButton.isEnabled = enabled
        
        // adjust search button alphas
        if enabled {
            phraseSearchButton.alpha = 1.0
            latLonSearchButton.alpha = 1.0
        } else {
            phraseSearchButton.alpha = 0.5
            latLonSearchButton.alpha = 0.5
        }
    }
}

// MARK: - ViewController (Notifications)

private extension ViewController {
    
    func subscribeToNotification(_ notification: NSNotification.Name, selector: Selector) {
        NotificationCenter.default.addObserver(self, selector: selector, name: notification, object: nil)
    }
    
    func unsubscribeFromAllNotifications() {
        NotificationCenter.default.removeObserver(self)
    }
}
