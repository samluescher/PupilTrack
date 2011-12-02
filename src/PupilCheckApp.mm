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
#import <AudioToolbox/AudioToolbox.h>


#include <algorithm>


#include "cinder/CinderResources.h"

#define CENTER_PAD 30
#define PAD 30
#define FLASH_DURATION 150
#define FONT_SIZE 60
#define PROCESSING_SKIP_FRAMES 3

#define DELAY_MEASURE 250

#define THRESH1 23
#define THRESH2 30

#define CROP_X1 260
#define CROP_Y1 185
#define CROP_X2 350
#define CROP_Y2 230

using namespace ci;
using namespace ci::app;
using namespace std;


class PupilCheckApp : public AppCocoaTouch {
public:	
	virtual void	setup();
	virtual void	update();
	virtual void	draw();
    virtual void    shutdown();
	virtual void	touchesBegan( TouchEvent event );

    void drawText(string str, Vec2f pos, gl::TextureFontRef &font);
    
	Capture mCapture;
	gl::Texture displayTexture, infoTexture;
    Surface captured, cropped;
    
	Quatf		mCubeQuat;
    
    int thresh1, thresh2;
    gl::TextureFontRef defaultFont, smallFont; 
    
	CameraPersp	mCam;
    Rectf screen;
    float brightL, brightR;
    
    bool sequenceStarted, calibrateStarted, drawCircle, useTestFrame, measured, hideMenu;
    int sequenceCounter;
    int sequenceFramesElapsed;

    float measurements[2];
    
    Surface testFrame;
    
    // Objective C
    CMMotionManager *motionManager;
    CMAttitude      *referenceAttitude;
    
    Area crop;

    SystemSoundID sndHold, snd123, sndBlip, sndHigh, sndLow, sndNotFound;
    
    float pupilRadius, prevPupilRadius;
    cv::Point2f pupilCenter;
    cv:: Mat threshDiff;
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
		mCapture = Capture(480, 360, Capture::getDevices()[1]); // front camera
		mCapture.start();
	}
	catch ( ... ) {
		console() << "Failed to initialize capture" << std::endl;
	}
    
    defaultFont = gl::TextureFont::create(Font("HelveticaNeue-Bold", FONT_SIZE));
    smallFont = gl::TextureFont::create(Font("HelveticaNeue-Light", FONT_SIZE / 2));

    testFrame = loadImage(loadResource("test_frame.png"));
    
    AudioServicesCreateSystemSoundID((CFURLRef)[NSURL fileURLWithPath: 
                                                [[NSBundle mainBundle] pathForResource:
                                                 @"hold" ofType:@"mp3"]], &sndHold);
    AudioServicesCreateSystemSoundID((CFURLRef)[NSURL fileURLWithPath: 
                                                [[NSBundle mainBundle] pathForResource:
                                                 @"123" ofType:@"mp3"]], &snd123);
    AudioServicesCreateSystemSoundID((CFURLRef)[NSURL fileURLWithPath: 
                                                [[NSBundle mainBundle] pathForResource:
                                                 @"blip" ofType:@"mp3"]], &sndBlip);
    AudioServicesCreateSystemSoundID((CFURLRef)[NSURL fileURLWithPath: 
                                                [[NSBundle mainBundle] pathForResource:
                                                 @"low" ofType:@"mp3"]], &sndLow);
    AudioServicesCreateSystemSoundID((CFURLRef)[NSURL fileURLWithPath: 
                                                [[NSBundle mainBundle] pathForResource:
                                                 @"high" ofType:@"mp3"]], &sndHigh);
    AudioServicesCreateSystemSoundID((CFURLRef)[NSURL fileURLWithPath: 
                                                [[NSBundle mainBundle] pathForResource:
                                                 @"notfound" ofType:@"mp3"]], &sndNotFound);

//    mCam.lookAt( Vec3f( 0, 0, -5 ), Vec3f::zero() );
//    mCam.setPerspective( 60, (float)getWindowWidth()/(float)getWindowHeight(), 1, 1000 );

    crop = Area(CROP_X1, CROP_Y1, CROP_X2, CROP_Y2);
    thresh1 = THRESH1;
    thresh2 = THRESH2;
    
    sequenceStarted = calibrateStarted = useTestFrame = hideMenu = false;
}

void PupilCheckApp::touchesBegan( TouchEvent event ) 
{
    int x = screen.getWidth() - event.getTouches().at(0).getY(); // Z since landscape
    int y = event.getTouches().at(0).getX(); // X since landscape
    bool top = y < screen.getCenter().y / 2;
    bool lower = y > screen.getCenter().y;
    bool lowest = y > screen.getLowerRight().y * .75f;
    bool right = x > screen.getCenter().x / 2; 
    console() << "touch " << x << "," <<  y << " " << screen.getCenter().x / 2 << endl;
    console() << "top " << top << endl;
    if (!sequenceStarted && !calibrateStarted) {
        if (top) {
            hideMenu = !hideMenu;
        } else {
            if (lower) {
                sequenceCounter = sequenceFramesElapsed = 0;
                sequenceStarted = true;
                measured = false;
            } else {
                calibrateStarted = true;
            }
        }
    } else if (calibrateStarted) {
        if (lower) {
            int step = 1;
            if (!right) {
                step *= -1;
            }
            if (!lowest) {
                thresh1 = max(0, min(255, thresh1 + step));
            } else {
                thresh2 = max(0, min(255, thresh2 + step));
            }
            if (thresh2 <= thresh1) {
                thresh2 = thresh1 + 1;
            }
        } else {
            if (right) {
                useTestFrame = !useTestFrame; 
            } else {
                calibrateStarted = false;
            }
        }
    } else {
        if (sequenceCounter < 1) {
            sequenceCounter++;
            measured = false;
            sequenceFramesElapsed = 0;
        } else {
            measured = sequenceStarted = false;
        }
    }
}


void PupilCheckApp::shutdown()
{
    [motionManager stopDeviceMotionUpdates];
    [motionManager release];
    [referenceAttitude release];
}

void extractPupilParams(cv::Mat &cropIm, int thresh1, int thresh2, cv::Mat &threshDiff, float &radius , cv::Point2f &center) {
    
    // Threshold the iamge
    cv::Mat threshIm2 , threshIm1;
    cv::threshold(cropIm, threshIm1, thresh1, 255 , cv::THRESH_BINARY_INV);
    cv::threshold(cropIm, threshIm2, thresh2, 255 , cv::THRESH_BINARY_INV);
    
    threshDiff = threshIm2 - threshIm1;
    
    // Return the radius of the Contours
    std::vector <std::vector<cv::Point> > contours;
    
    cv::findContours(threshDiff,
                     contours, // a vector of contours
                     CV_RETR_EXTERNAL, // retrieve the external contours
                     CV_CHAIN_APPROX_NONE); // all pixels of each contours
    
    // cv::Mat result(cropIm.size(),CV_8U,cv::Scalar(0));
    
    
    
    //imshow("Contours" , cropIm);
    //Display Contours*******************
    
    
    int cmin= 15 ; // minimum contour length
    int cmax= 100; // maximum contour length
    
    std::vector <std::vector<cv::Point> >::iterator itc= contours.begin();
    
    cv::Point2f ctr;
    float rad, prevRad = 0;
    
    while (itc != contours.end()) {
        if (itc->size() < cmin || itc->size() > cmax) {
            itc = contours.erase(itc);
        } else {
            // find largest 
            cv::minEnclosingCircle(cv::Mat(*itc), ctr, rad);
            if (rad > prevRad) {
              radius = rad;
              center = ctr;
            }
            prevRad = rad;
            ++itc;
        }
    }

    //Display Contours*******************
    cv::drawContours(cropIm,contours,
                     -1, // draw all contours
                     cv::Scalar(255), // in white
                     1); // with a thickness of 2
    
    if (contours.size() > 0) {
//        cv::minEnclosingCircle(cv::Mat(contours[0]),center,radius);
    } else {
        radius = 0;
    }
}


void PupilCheckApp::update()
{
	if (mCapture && mCapture.checkNewFrame()) {
        captured = mCapture.getSurface();
        if (!useTestFrame) {
            cropped = captured.clone(crop);
        } else {
            cropped = testFrame;
        }
            
        if ((sequenceStarted && !measured) || calibrateStarted) {
            
            if (getElapsedFrames() % PROCESSING_SKIP_FRAMES == 0) {
                
                cv::Mat matCropped = toOcv(cropped);
                std::vector<cv::Mat> channels;
                cv::split(matCropped, channels);
                //cv::cvtColor(mat , matGray , CV_BGR2GRAY);
                cv::Mat matGray = channels[0];
                
                extractPupilParams(matGray, thresh1, thresh2, threshDiff, pupilRadius, pupilCenter);
                displayTexture = gl::Texture(fromOcv(matGray));
                //infoTexture = gl::Texture(fromOcv(threshDiff));
            }
        } else {
            if (!measured) {
                displayTexture = gl::Texture(cropped);
            }
        }
    
    }

    if (sequenceFramesElapsed == DELAY_MEASURE) {
        measured = pupilRadius > 0;
        if (measured) {
            measurements[sequenceCounter] = pupilRadius;
        }
    }
                
    /*if (captured && getElapsedFrames() % 20 == 0) {
    
        console() << captured.getWidth() << "*" << captured.getHeight() << std::endl;
        
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
    }*/
        

    // The translation and rotation components of the modelview matrix
    CMQuaternion quat;
	
    CMDeviceMotion *deviceMotion = motionManager.deviceMotion;		
    CMAttitude *attitude = deviceMotion.attitude;
    
    quat	= attitude.quaternion;
    mCubeQuat	= Quatf( quat.w, quat.x, -quat.y, quat.z );

    
}

void PupilCheckApp::drawText(string str, Vec2f pos, gl::TextureFontRef &font) 
{
    font->drawString(str, pos);
    font->drawString(str, Vec2f(pos.x + screen.getCenter().x, pos.y));
}


void PupilCheckApp::draw()
{
    gl::enableAlphaBlending();
    
    
    if (sequenceStarted) {
        gl::clear( Color( 0, 0, 0 ) );
    } else {
        gl::clear( Color( .2f, .2f, .2f ) );
    }
    gl::setMatricesWindow( getWindowWidth(), getWindowHeight() );
	
    
    
	if (captured) {
        gl::pushMatrices();
        /*
        // landscape right
        gl::translate(Vec2f(getWindowWidth(),0));     
        gl::rotate(Vec3f(0,0,90.0f));
        */

        // landscape left
        gl::translate(Vec2f(0, getWindowHeight()));     
        gl::rotate(Vec3f(0,0,270.0f));        
        
        if (sequenceStarted) {
            if (sequenceFramesElapsed == 0) {
                AudioServicesPlaySystemSound (sndHold);
            }
            
            if (sequenceFramesElapsed == DELAY_MEASURE - 120) {
                AudioServicesPlaySystemSound (snd123);
            } 

            if (sequenceFramesElapsed == DELAY_MEASURE) {
                AudioServicesPlaySystemSound (sndBlip);
            } 
            
            if (sequenceFramesElapsed == DELAY_MEASURE + 30) {
                if (pupilRadius > 0) {
                    if (sequenceCounter == 0) {
                        AudioServicesPlaySystemSound (sndLow);
                    } else {
                        AudioServicesPlaySystemSound (sndHigh);
                    }
                } else {
                    AudioServicesPlaySystemSound (sndNotFound);
                }
            } 
            
            if (sequenceCounter == 0) {
                brightR = 0.0f;
                brightL = 0.0f;
            } else {
                brightR = 0.0f;
                brightL = 1.0f;
            }

            gl::color(brightL, brightL, brightL);
            gl::drawSolidRect(Rectf(screen.getUpperLeft().x, screen.getUpperLeft().y, screen.getCenter().x - CENTER_PAD, screen.getLowerRight().y));

            gl::color(brightR, brightR, brightR);
            gl::drawSolidRect(Rectf(screen.getCenter().x + CENTER_PAD, screen.getUpperLeft().y, screen.getLowerRight().x, screen.getLowerRight().y));

            sequenceFramesElapsed++;
        }

        float ratioX = (screen.getWidth() / 2.0f) / displayTexture.getWidth();
        float ratioY = (screen.getHeight() / 2.0f) / displayTexture.getHeight();
        
        if (!sequenceStarted || measured) {
            gl::color(1, 1, 1, 1);
            if (!hideMenu || measured) {
                gl::draw(displayTexture, Rectf(screen.getUpperLeft().x, screen.getUpperLeft().y, screen.getCenter().x, screen.getCenter().y));
                gl::draw(displayTexture, Rectf(screen.getCenter().x, screen.getUpperLeft().y, screen.getLowerRight().x, screen.getCenter().y));
            } else {
                gl::draw(displayTexture, Vec2f(screen.getUpperLeft().x, screen.getUpperLeft().y));
            }
        }
            
        if (!sequenceStarted && !calibrateStarted && !hideMenu) {
            gl::color(1, 1, 1, 1);
            drawText("calibrate", Vec2f(PAD, screen.getCenter().y - PAD), defaultFont);
            drawText("begin", Vec2f(PAD, screen.getCenter().y + PAD + FONT_SIZE / 2), defaultFont);
        }

        if ((sequenceStarted && measured) || calibrateStarted) {
            if (pupilRadius > 0) {
                gl::color(1.0f, 1.0f, 0, .4f);
                gl::drawSolidCircle(Vec2f(pupilCenter.x * ratioX + screen.getUpperLeft().x, pupilCenter.y * ratioY + screen.getUpperLeft().y), pupilRadius * ratioX);
                gl::drawSolidCircle(Vec2f(pupilCenter.x * ratioX + screen.getCenter().x, pupilCenter.y * ratioY + screen.getUpperLeft().y), pupilRadius * ratioX);
                console() << pupilCenter.x << "," << pupilCenter.y << " " << pupilRadius << endl;
                if (measured) {
                    gl::color(1.0f, 1.0f, 1.0, 1);
                    drawText((sequenceCounter == 0 ? "low stimulus radius:" : "high stimulus radius:"), Vec2f(PAD, PAD + FONT_SIZE * .5), smallFont);
                    stringstream ss;
                    ss.precision(2);
                    ss << pupilRadius;
                    gl::color(1.0f, 1.0f, 0, 1);
                    drawText(toString(ss.str()), Vec2f(PAD, PAD + FONT_SIZE * 1.5), defaultFont);
                    if (sequenceCounter > 0 && pupilRadius < measurements[sequenceCounter - 1]) {
                        gl::color(1.0f, 1.0f, 1.0, 1);
                        ss.str("");
                        float percentage = 100 - (pupilRadius * 100 / measurements[sequenceCounter - 1]);
                        ss << percentage << "% constricted";
                        drawText(toString(ss.str()), Vec2f(PAD, PAD + FONT_SIZE * 2.15), smallFont);
                    }
                }
            }

            if (infoTexture) {
                gl::color(1, 1, 1, 1);
                gl::draw(infoTexture, Rectf(screen.getUpperLeft().x, screen.getCenter().y, screen.getCenter().x, screen.getLowerRight().y));
                gl::draw(infoTexture, Rectf(screen.getCenter().x, screen.getCenter().y, screen.getLowerRight().x, screen.getLowerRight().y));
            }
        }

        if (calibrateStarted) {
            gl::color(1, 1, 1, 1);
            drawText("ok", Vec2f(PAD, screen.getCenter().y - PAD), defaultFont);
            if (useTestFrame) {
                gl::color(1, 1, 1, 1);
            } else {
                gl::color(.3f, .3f, .3f);
            }
            drawText("demo", Vec2f(screen.getCenter().x * .55f, screen.getCenter().y - PAD), defaultFont);
            
            int y = screen.getCenter().y + PAD * 3 + FONT_SIZE / 2;
            gl::color(.3f, .3f, .3f);
            drawText("-", Vec2f(PAD, y), defaultFont);
            gl::color(.6f, .6f, .6f);
            drawText("thresh1", Vec2f(PAD * 3, y - FONT_SIZE * .1), smallFont);
            gl::color(.7f, .7f, .7f);
            drawText("+", Vec2f(screen.getCenter().x - PAD * 2, y), defaultFont);
            gl::color(1, 1, 1);
            drawText(toString(thresh1), Vec2f(screen.getCenter().x * .55f, y), defaultFont);
            
            y += FONT_SIZE * 2;
            gl::color(.3f, .3f, .3f);
            drawText("-", Vec2f(PAD, y), defaultFont);
            gl::color(.6f, .6f, .6f);
            drawText("thresh2", Vec2f(PAD * 3, y - FONT_SIZE * .1), smallFont);
            gl::color(.7f, .7f, .7f);
            drawText("+", Vec2f(screen.getCenter().x - PAD * 2, y), defaultFont);
            gl::color(1, 1, 1);
            drawText(toString(thresh2), Vec2f(screen.getCenter().x * .55f, y), defaultFont);
        }
            
        //gl::translate(Vec2f(0, screen.getHeight() / 2));
        //gl::draw(modTexture);
        
        
        // draw orientation test dots
        /*
        gl::color(1.0f, 0, 0);
        gl::drawSolidCircle(screen.getUpperLeft(),80,80);
        gl::color(0, 1.0f, 0);
        gl::drawSolidCircle(screen.getCenter(),80,80);
        gl::color(0, 0, 1.0f);
        gl::drawSolidCircle(screen.getLowerRight(),80,80);
         */
        
        /*gl::color(1, 1, 1);
        font->drawString("thresh1:"+toString(thresh1), Vec2f(1, 1));
        gl::translate(screen.getWidth() / 4, 0);
        font->drawString("thresh2:"+toString(thresh2), Vec2f(1, 1));
        */
         
        gl::popMatrices();
	}
}


#if defined( CINDER_COCOA_TOUCH )
CINDER_APP_COCOA_TOUCH( PupilCheckApp, RendererGl )
#else
CINDER_APP_BASIC( PupilCheckApp, RendererGl )
#endif
