#include "cinder/Cinder.h"
#include "cinder/app/AppCocoaTouch.h"
#include "cinder/app/Renderer.h"
#include "cinder/Surface.h"
#include "cinder/gl/Texture.h"
#include "cinder/gl/TextureFont.h"
#include "cinder/Camera.h"

#include "cinder/Vector.h"
#include "cinder/Capture.h"
#include "CinderOpenCV.h"
#include "cinder/Utilities.h"

#import <CoreMotion/CoreMotion.h>

using namespace ci;
using namespace ci::app;
using namespace std;

class PupilCheckApp : public AppCocoaTouch {
public:	
	virtual void	setup();
	virtual void	update();
	virtual void	draw();
    virtual void    shutdown();
    virtual void mouseDrag(MouseEvent event);
	virtual void	mouseDown( MouseEvent event );
    
	Capture mCapture;
	gl::Texture mTexture;
	gl::Texture modTexture;
    Surface captured;
    
	Quatf		mCubeQuat;
    
    float thresh1, thresh2;
    gl::TextureFontRef font; 
    
	CameraPersp	mCam;
    Rectf screen;
    float brightL, brightR;
    
    // Objective C
    CMMotionManager *motionManager;
    CMAttitude      *referenceAttitude;
};


void PupilCheckApp::setup()
{
    motionManager = [[CMMotionManager alloc] init];
    [motionManager startDeviceMotionUpdates];
    [[UIApplication sharedApplication] setStatusBarHidden:YES];
    
    brightL = 0;
    brightR = 0;
    
    // width and height are reversed because of horizontal orientation
    screen = Rectf(0, 0, getWindowHeight(), getWindowWidth());
    
    CMDeviceMotion *dm = motionManager.deviceMotion;
    referenceAttitude = [dm.attitude retain];
	
	try {
		mCapture = Capture(640, 480, Capture::getDevices()[1]); // front camera
		mCapture.start();
	}
	catch ( ... ) {
		console() << "Failed to initialize capture" << std::endl;
	}
    
    font = gl::TextureFont::create(Font("Helvetica", 30));

//    mCam.lookAt( Vec3f( 0, 0, -5 ), Vec3f::zero() );
//    mCam.setPerspective( 60, (float)getWindowWidth()/(float)getWindowHeight(), 1, 1000 );

    thresh1 = 30.0f;
    thresh2 = 10.0f;    
}

void PupilCheckApp::mouseDown( MouseEvent event )
{
	console() << "Mouse down @ " << event.getPos() << std::endl;
}

void PupilCheckApp::mouseDrag(MouseEvent event)
{
	// add wherever the user drags to the end of our list of points
	console() << "drag " << event.getPos();
}

void PupilCheckApp::shutdown()
{
    [motionManager stopDeviceMotionUpdates];
    [motionManager release];
    [referenceAttitude release];
}

void PupilCheckApp::update()
{
	if (mCapture && mCapture.checkNewFrame()) {
        captured = mCapture.getSurface();
    }
    
    
    if (captured && getElapsedFrames() % 20 == 0) {
    
        cv::Mat mat = toOcv(captured);
        
        cv::Mat matGray , matGray1, matGray2, result, equalIm;

        std::vector<cv::Mat> channels;
        
        cv::split(mat, channels);
        
        
        //cv::cvtColor(mat , matGray , CV_BGR2GRAY);
        matGray = channels[0];
        
        //cv::(matGray , matGray);
        //cv::equalizeHist(matGray, equalIm);
        
        //cv::threshold(matGray, matGray1, 5, 255, CV_THRESH_BINARY_INV);
        
        cv::threshold(matGray, matGray1, thresh1, 255, CV_THRESH_BINARY_INV);
        //cv::threshold(matGray, matGray2, thresh2, 255, CV_THRESH_BINARY);

        //result = matGray2 - matGray1;
        result = matGray1;
        
        //cv::threshold(equalIm, equalIm, 30, 255, CV_THRESH_BINARY);
		modTexture = gl::Texture( fromOcv(result) );

		mTexture = gl::Texture(fromOcv(matGray));
    }

    // The translation and rotation components of the modelview matrix
    CMQuaternion quat;
	
    CMDeviceMotion *deviceMotion = motionManager.deviceMotion;		
    CMAttitude *attitude = deviceMotion.attitude;
    
    quat	= attitude.quaternion;
    mCubeQuat	= Quatf( quat.w, quat.x, -quat.y, quat.z );

}

void PupilCheckApp::draw()
{
	gl::clear( Color( 1.0f, 0, 0 ) );
	gl::setMatricesWindow( getWindowWidth(), getWindowHeight() );
	
    
    
	if( mTexture ) {
        gl::pushMatrices();
        /*
        // landscape right
        gl::translate(Vec2f(getWindowWidth(),0));     
        gl::rotate(Vec3f(0,0,90.0f));
        */

        // landscape left
        gl::translate(Vec2f(0, getWindowHeight()));     
        gl::rotate(Vec3f(0,0,270.0f));        

        if (getElapsedFrames() / 20 % 2 == 0) {
            brightR = 0.0f;
            brightL = 1.0f;
        } else {
            brightR = 0.0f;
            brightL = 1.0f;
        }
        
        gl::color(brightL, brightL, brightL);
        gl::drawSolidRect(Rectf(screen.getUpperLeft().x, screen.getUpperLeft().y, screen.getLowerRight().x, screen.getLowerRight().y));
        gl::color(brightR, brightR, brightR);
        gl::drawSolidRect(Rectf(screen.getCenter().x, screen.getUpperLeft().y, screen.getLowerRight().x, screen.getLowerRight().y));

        gl::color(1, 1, 1);
        gl::translate(screen.getCenter().x, screen.getUpperLeft().y);
        gl::draw(mTexture);
//        gl::draw(gl::Texture(captured.getChannelRed()));

        gl::translate(Vec2f(0, screen.getHeight() / 2));
        gl::draw(modTexture);
//        gl::draw(gl::Texture(captured.getChannelBlue()));
        
        // draw orientation test dots
        /*
        gl::color(1.0f, 0, 0);
        gl::drawSolidCircle(screen.getUpperLeft(),80,80);
        gl::color(0, 1.0f, 0);
        gl::drawSolidCircle(screen.getCenter(),80,80);
        gl::color(0, 0, 1.0f);
        gl::drawSolidCircle(screen.getLowerRight(),80,80);
         */
        
        gl::color(1, 1, 1);
        font->drawString("thresh1:"+toString(thresh1), Vec2f(1, 1));
        gl::translate(screen.getWidth() / 4, 0);
        font->drawString("thresh2:"+toString(thresh2), Vec2f(1, 1));

        gl::popMatrices();
	}
}


#if defined( CINDER_COCOA_TOUCH )
CINDER_APP_COCOA_TOUCH( PupilCheckApp, RendererGl )
#else
CINDER_APP_BASIC( PupilCheckApp, RendererGl )
#endif
