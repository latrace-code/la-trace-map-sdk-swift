Pod::Spec.new do |s|
  s.name             = 'LaTraceMapSDK'
  s.version          = '1.0.3'
  s.summary          = 'SDK carto La Trace pour iOS : le vrai /explore pilote depuis Swift.'

  s.description      = <<~DESC
    La carte est le vrai /explore La Trace, charge en mode nu dans une WKWebView et
    pilote depuis Swift. L'hote pousse ses lieux, ecoute les evenements et garde toute
    son interface en natif. Zero stockage : rien n'est conserve cote La Trace.
  DESC

  s.homepage         = 'https://github.com/latrace-code/la-trace-map-sdk-swift'
  s.license          = { :type => 'Proprietary', :file => 'LICENSE' }
  s.author           = { 'La Trace' => 'contact@latrace.com' }
  s.source           = {
    :git => 'https://github.com/latrace-code/la-trace-map-sdk-swift.git',
    :tag => s.version.to_s
  }

  s.ios.deployment_target = '15.0'
  s.swift_versions   = ['5.9']

  s.source_files     = 'Sources/LaTraceMapSDK/**/*.swift'
  s.frameworks       = 'WebKit', 'CoreLocation', 'UIKit', 'Combine'
end
