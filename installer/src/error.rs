/*
    Internal:
        1000(one thousand): internal error

    PermissionDenied:
        2000(two thousand): permission denied: cannot access the application directory in the home directory
        2001(two thousand one): permission denied: cannot access the application directory in the Macintosh HD/Applications directory
    
    ExecutionFailed:
        3000(three thousand): failed to run the installer
        3001(three thousand one): failed to update using the installer
        3002(three thousand two): the installer completed successfully, but failed to launch the installed WebSnapshot.app
        3003(three thousand three): the installer completed successfully and the update was applied, but failed to launch the updated WebSnapshot.app

    NetworkDown:
        4000(four thousand): check that your computer is connected to the Internet
        4001(four thousand one): the network connection was lost. check your Internet connection and try again 
        
    NetworkUnreachable:
        5000(five thousand): Internet connectivity confirmed, but the repository could not be reached
        5001(five thousand one): access to the repository was denied
        
    InvalidDownload:
        6000(six thousand): download from the repository was interrupted
        6001(six thousand one): the installer encountered an error and failed to download

    InvalidInstall:
        7000(seven thousand): the download completed successfully, but failed to install WebSnapshot.app
        7001(seven thousand one): the installer crashed during installation  
*/

#[derive(Debug)]
pub enum ErrorCode{
    OneThousand = 1000,
    TwoThousand = 2000,
    TwoThousandOne = 2001,
    ThreeThousand = 3000,
    ThreeThousandOne = 3001,
    ThreeThousandTow = 3002,
    ThreeThousandThree = 3003,
    FourThousand = 4000,
    FourThousandOne = 4001,
    FiveThousand = 5000,
    FiveThousandOne = 5001,
    SixThousand = 6000,
    SixThousandOne = 6001,
    SevenThousand = 7000,
    SevenThousandOne = 7001,
}


#[derive(Debug)]
pub enum ErrorKind{
    Internal,
    PermissionDenied,
    ExecutionFailed,
    NetworkDown,
    NetworkUnreachable,
    InvalidDownload,
    InvalidInstall,
}

#[derive(Debug)]
pub struct Error{
    code:ErrorCode,
    kind:ErrorKind,
}

impl Error{
    pub fn code(&self) -> &ErrorCode{
        &self.code
    }

    pub fn kind(&self) -> &ErrorKind{
        &self.kind
    }

    pub fn message(&self) -> &str{
        match &self.code{
            ErrorCode::OneThousand => "internal error",
            ErrorCode::TwoThousand => "permission denied: cannot access the application directory in the home directory",
            ErrorCode::TwoThousandOne => "permission denied: cannot access the application directory in the Macintosh HD/Applications directory",
            ErrorCode::ThreeThousand => "failed to run the installer",
            ErrorCode::ThreeThousandOne => "failed to update using the installer",
            ErrorCode::ThreeThousandTow => "the installer completed successfully, but failed to launch the installed WebSnapshot.app",
            ErrorCode::ThreeThousandThree => "the installer completed successfully and the update was applied, but failed to launch the updated WebSnapshot.app",
            ErrorCode::FourThousand => "check that your computer is connected to the Internet",
            ErrorCode::FourThousandOne => "the network connection was lost. check your Internet connection and try again ",
            ErrorCode::FiveThousand => "Internet connectivity confirmed, but the repository could not be reached",
            ErrorCode::FiveThousandOne => "access to the repository was denied",
            ErrorCode::SixThousand => "download from the repository was interrupted",
            ErrorCode::SixThousandOne => "the installer encountered an error and failed to download",
            ErrorCode::SevenThousand => "the download completed successfully, but failed to install WebSnapshot.app",
            ErrorCode::SevenThousandOne => "the installer crashed during installation",
        }
    }
}
