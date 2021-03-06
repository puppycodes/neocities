require './environment.rb'
require './app_helpers.rb'

use Rack::Session::Cookie, key:          'neocities',
                           path:         '/',
                           expire_after: 31556926, # one year in seconds
                           secret:       $config['session_secret'],
                           httponly: true,
                           same_site: true,
                           secure: ENV['RACK_ENV'] == 'production'

use Rack::Recaptcha, public_key: $config['recaptcha_public_key'], private_key: $config['recaptcha_private_key']
use Rack::TempfileReaper
helpers Rack::Recaptcha::Helpers

helpers do
  def site_change_file_display_class(filename)
    return 'html' if filename.match(Site::HTML_REGEX)
    return 'image' if filename.match(Site::IMAGE_REGEX)
    'misc'
  end

  def csrf_token_input_html
    %{<input name="csrf_token" type="hidden" value="#{csrf_token}">}
  end
end

set :protection, :frame_options => "ALLOW-FROM #{$config['surf_iframe_source']}"

GEOCITIES_NEIGHBORHOODS = %w{
  area51
  athens
  augusta
  baja
  bourbonstreet
  capecanaveral
  capitolhill
  collegepark
  colosseum
  enchantedforest
  hollywood
  motorcity
  napavalley
  nashville
  petsburgh
  pipeline
  rainforest
  researchtriangle
  siliconvalley
  soho
  sunsetstrip
  timessquare
  televisioncity
  tokyo
  vienna
  yosemite
}.freeze

def redirect_to_internet_archive_for_geocities_sites
  match = request.path.match /^\/(\w+)\/.+$/i
  if match && GEOCITIES_NEIGHBORHOODS.include?(match.captures.first.downcase)
    redirect "https://wayback.archive.org/http://geocities.com/#{request.path}"
  end
end

before do
  if request.path.match /^\/api\//i
    @api = true
    content_type :json
  elsif request.path.match /^\/webhooks\//
    # Skips the CSRF/validation check for stripe web hooks
  elsif email_not_validated? && !(request.path =~ /^\/site\/.+\/confirm_email|^\/settings\/change_email|^\/signout|^\/welcome|^\/supporter/)
    redirect "/site/#{current_site.username}/confirm_email"
  else
    content_type :html, 'charset' => 'utf-8'
    redirect '/' if request.post? && !csrf_safe?
  end
end

not_found do
  api_not_found if @api
  redirect_to_internet_archive_for_geocities_sites
  @title = 'Not Found'
  erb :'not_found'
end

error do
  EmailWorker.perform_async({
    from: 'web@neocities.org',
    to: 'errors@neocities.org',
    subject: "[Neocities Error] #{env['sinatra.error'].class}: #{env['sinatra.error'].message}",
    body: erb(:'templates/email/error', layout: false),
    no_footer: true
  })

  if @api
    api_error 500, 'server_error', 'there has been an unknown server error, please try again later'
  end

  erb :'error'
end

Dir['./app/**/*.rb'].each {|f| require f}
